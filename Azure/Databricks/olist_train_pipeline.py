# Databricks notebook source
# MAGIC %md
# MAGIC # Olist — Pipeline automático de entrenamiento (churn / 2ª compra)
# MAGIC
# MAGIC Port del `sprint2_pipeline.ipynb` para ejecución como **job programado** en Azure Databricks.
# MAGIC Lee los CSV del blob storage público (`olist-data`), construye la tabla maestra por snapshots
# MAGIC mensuales sin fuga de información, entrena dos modelos, elige el mejor por AUC out-of-time
# MAGIC y registra el pipeline final con **MLflow**.

# COMMAND ----------

import numpy as np
import pandas as pd
import mlflow
import mlflow.sklearn

dbutils.widgets.text("horizon_days", "90")
dbutils.widgets.text("snapshot_start", "2017-01-31")
dbutils.widgets.text("snapshot_end", "2018-07-31")

H = int(dbutils.widgets.get("horizon_days"))
SNAPSHOT_START = dbutils.widgets.get("snapshot_start")
SNAPSHOT_END = dbutils.widgets.get("snapshot_end")
RANDOM_STATE = 42

BLOB = "https://oliststorage40548.blob.core.windows.net/olist-data"
INVALID_STATUS = ["canceled", "unavailable"]
ORDER_DATE_COLS = [
    "order_purchase_timestamp", "order_approved_at",
    "order_delivered_carrier_date", "order_delivered_customer_date",
    "order_estimated_delivery_date",
]

# COMMAND ----------

# MAGIC %md ## 1. Carga de datos desde el blob público

# COMMAND ----------

def load_tables() -> dict:
    return {
        "orders": pd.read_csv(f"{BLOB}/olist_orders_dataset.csv",
                              parse_dates=ORDER_DATE_COLS),
        "customers": pd.read_csv(f"{BLOB}/olist_customers_dataset.csv"),
        "order_items": pd.read_csv(f"{BLOB}/olist_order_items_dataset.csv",
                                   parse_dates=["shipping_limit_date"]),
        "order_payments": pd.read_csv(f"{BLOB}/olist_order_payments_dataset.csv"),
        "order_reviews": pd.read_csv(f"{BLOB}/olist_order_reviews_dataset.csv",
                                     parse_dates=["review_creation_date",
                                                  "review_answer_timestamp"]),
        "products": pd.read_csv(f"{BLOB}/olist_products_dataset.csv"),
        "sellers": pd.read_csv(f"{BLOB}/olist_sellers_dataset.csv"),
        "category_translation": pd.read_csv(
            f"{BLOB}/product_category_name_translation.csv"),
        "geo_lookup": pd.read_csv(f"{BLOB}/geolocation_zip_lookup.csv"),
    }

tables = load_tables()
print("tablas cargadas:", {k: len(v) for k, v in tables.items()})

# COMMAND ----------

# MAGIC %md ## 2. Tabla pedido enriquecida (espejo de `dbo.order_enrichment`)

# COMMAND ----------

def haversine_km(lat1, lng1, lat2, lng2):
    lat1, lng1, lat2, lng2 = map(np.radians, [lat1, lng1, lat2, lng2])
    a = (np.sin((lat2 - lat1) / 2) ** 2
         + np.cos(lat1) * np.cos(lat2) * np.sin((lng2 - lng1) / 2) ** 2)
    return 2 * 6371.0 * np.arcsin(np.sqrt(a))


def build_order_enrichment(tables: dict) -> pd.DataFrame:
    orders = tables["orders"]
    oc = orders.merge(tables["customers"], on="customer_id", how="left")
    oc = oc[~oc.order_status.isin(INVALID_STATUS)].copy()

    items = tables["order_items"]
    items_agg = items.groupby("order_id", as_index=False).agg(
        n_items=("order_item_id", "max"), price=("price", "sum"),
        freight_value=("freight_value", "sum"),
        n_sellers=("seller_id", "nunique"))
    items_agg["order_value"] = items_agg.price + items_agg.freight_value

    cat = (items.merge(tables["products"][["product_id", "product_category_name"]],
                       on="product_id", how="left")
                .merge(tables["category_translation"],
                       on="product_category_name", how="left"))
    cat["top_category"] = cat.product_category_name_english.fillna(
        cat.product_category_name)
    cat = (cat.groupby(["order_id", "top_category"], as_index=False)
              .agg(cat_value=("price", "sum"))
              .sort_values(["order_id", "cat_value", "top_category"])
              .groupby("order_id").tail(1)[["order_id", "top_category"]])

    pay = tables["order_payments"]
    pay_tot = pay.groupby("order_id", as_index=False).agg(
        payment_value=("payment_value", "sum"),
        payment_installments=("payment_installments", "max"))
    pay_dom = (pay.sort_values("payment_value")
                  .groupby("order_id").tail(1)[["order_id", "payment_type"]])

    rev = (tables["order_reviews"].groupby("order_id", as_index=False)
           .agg(review_score=("review_score", "mean")))

    geo = tables["geo_lookup"].set_index("geolocation_zip_code_prefix")[["lat", "lng"]]
    dist = (items[["order_id", "seller_id"]]
            .merge(tables["sellers"][["seller_id", "seller_zip_code_prefix"]],
                   on="seller_id", how="left")
            .merge(oc[["order_id", "customer_zip_code_prefix"]],
                   on="order_id", how="left")
            .join(geo.add_prefix("seller_"), on="seller_zip_code_prefix")
            .join(geo.add_prefix("customer_"), on="customer_zip_code_prefix"))
    dist["distance_km"] = haversine_km(dist.seller_lat, dist.seller_lng,
                                       dist.customer_lat, dist.customer_lng)
    dist = dist.groupby("order_id", as_index=False).agg(
        distance_km=("distance_km", "mean"))

    oe = (oc[["order_id", "customer_unique_id", "customer_state",
              "customer_zip_code_prefix", "order_status",
              "order_purchase_timestamp", "order_delivered_customer_date",
              "order_estimated_delivery_date"]]
          .merge(items_agg, on="order_id", how="left")
          .merge(cat, on="order_id", how="left")
          .merge(pay_tot, on="order_id", how="left")
          .merge(pay_dom, on="order_id", how="left")
          .merge(rev, on="order_id", how="left")
          .merge(dist, on="order_id", how="left"))
    oe["delivery_days"] = (oe.order_delivered_customer_date
                           - oe.order_purchase_timestamp).dt.days
    oe["delay_days"] = (oe.order_delivered_customer_date
                        - oe.order_estimated_delivery_date).dt.days
    oe["is_late"] = np.where(oe.order_delivered_customer_date.isna(), np.nan,
                             (oe.delay_days > 0).astype(float))
    return oe


orders_enriched = build_order_enrichment(tables)
print("order_enrichment:", orders_enriched.shape)

# COMMAND ----------

# MAGIC %md ## 3. Tabla maestra por snapshot (espejo de `dbo.sp_build_master_table`)

# COMMAND ----------

def dominant_by_customer(obs: pd.DataFrame, col: str) -> pd.Series:
    counts = (obs.dropna(subset=[col])
                 .groupby(["customer_unique_id", col]).size()
                 .reset_index(name="n")
                 .sort_values(["customer_unique_id", "n", col]))
    return counts.groupby("customer_unique_id")[col].last()


def build_master_table(orders_enriched, cutoff_date, horizon_days=H):
    t = pd.Timestamp(cutoff_date)
    t_end = t + pd.Timedelta(days=horizon_days)
    obs = orders_enriched[orders_enriched.order_purchase_timestamp <= t]
    fut = set(orders_enriched.loc[
        (orders_enriched.order_purchase_timestamp > t)
        & (orders_enriched.order_purchase_timestamp <= t_end),
        "customer_unique_id"])
    g = obs.groupby("customer_unique_id")
    master = pd.DataFrame({
        "recency_days": (t - g.order_purchase_timestamp.max()).dt.days,
        "frequency": g.order_id.nunique(),
        "monetary": g.order_value.sum(),
        "tenure_days": (t - g.order_purchase_timestamp.min()).dt.days,
        "avg_items": g.n_items.mean(),
        "avg_order_value": g.order_value.mean(),
        "avg_freight_value": g.freight_value.mean(),
        "max_installments": g.payment_installments.max(),
        "customer_state": dominant_by_customer(obs, "customer_state"),
        "top_category": dominant_by_customer(obs, "top_category"),
        "payment_type": dominant_by_customer(obs, "payment_type"),
        "avg_review_score": g.review_score.mean(),
        "avg_delay_days": g.delay_days.mean(),
        "pct_late_deliveries": g.is_late.mean(),
        "avg_distance_km": g.distance_km.mean(),
    }).reset_index()
    master["purchased_next_h"] = master.customer_unique_id.isin(fut).astype(int)
    master["is_repeat"] = np.where(master.frequency == 1,
                                   master.purchased_next_h, np.nan)
    master["snapshot_date"] = t
    return master

# COMMAND ----------

# MAGIC %md ## 4. Panel de snapshots mensuales y partición out-of-time

# COMMAND ----------

cutoffs = pd.date_range(SNAPSHOT_START, SNAPSHOT_END, freq="ME")
snapshots = []
for t in cutoffs:
    snap = build_master_table(orders_enriched, t)
    snap = snap[snap.frequency == 1]          # población del MVP: primerizos
    snapshots.append(snap)

panel = pd.concat(snapshots, ignore_index=True)
panel = (panel.sort_values("snapshot_date")
              .drop_duplicates("customer_unique_id", keep="first")
              .reset_index(drop=True))
panel["is_repeat"] = panel.is_repeat.astype(int)

panel["split"] = np.select(
    [panel.snapshot_date <= "2017-12-31",
     panel.snapshot_date <= "2018-03-31"],
    ["train", "validation"], default="backtest")
print(panel.split.value_counts())

# COMMAND ----------

# MAGIC %md ## 5. Entrenamiento, selección del modelo y registro en MLflow

# COMMAND ----------

from sklearn.compose import ColumnTransformer
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (average_precision_score, f1_score,
                             precision_score, recall_score, roc_auc_score)
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

# Selección heredada del Sprint 2 (tenure_days y avg_order_value descartadas por VIF)
SELECTED_NUM = ["recency_days", "monetary", "avg_items", "avg_freight_value",
                "max_installments", "avg_review_score", "avg_delay_days",
                "pct_late_deliveries", "avg_distance_km"]
SELECTED_CAT = ["customer_state", "top_category", "payment_type"]
FEATURES = SELECTED_NUM + SELECTED_CAT
TARGET = "is_repeat"

def make_preprocessor():
    return ColumnTransformer([
        ("num", Pipeline([("imputer", SimpleImputer(strategy="median")),
                          ("scaler", StandardScaler())]), SELECTED_NUM),
        ("cat", Pipeline([("imputer", SimpleImputer(strategy="most_frequent")),
                          ("onehot", OneHotEncoder(handle_unknown="ignore",
                                                   min_frequency=200))]),
         SELECTED_CAT),
    ])

MODELS = {
    "logistic_regression": LogisticRegression(
        class_weight="balanced", max_iter=2000, random_state=RANDOM_STATE),
    "hist_gradient_boosting": HistGradientBoostingClassifier(
        class_weight="balanced", random_state=RANDOM_STATE),
}

train = panel[panel.split == "train"]
valid = panel[panel.split == "validation"]
backtest = panel[panel.split == "backtest"]

mlflow.set_experiment("/Shared/olist-churn-experiment")

def evaluate(y_true, proba, prefix):
    pred = (proba >= 0.5).astype(int)
    return {
        f"{prefix}_auc": roc_auc_score(y_true, proba),
        f"{prefix}_pr_auc": average_precision_score(y_true, proba),
        f"{prefix}_recall": recall_score(y_true, pred),
        f"{prefix}_precision": precision_score(y_true, pred, zero_division=0),
        f"{prefix}_f1": f1_score(y_true, pred),
    }

results = {}
with mlflow.start_run(run_name="olist-churn-training") as parent:
    mlflow.log_params({"horizon_days": H, "snapshot_start": SNAPSHOT_START,
                       "snapshot_end": SNAPSHOT_END,
                       "n_train": len(train), "n_validation": len(valid),
                       "n_backtest": len(backtest)})
    for name, clf in MODELS.items():
        with mlflow.start_run(run_name=name, nested=True):
            pipe = Pipeline([("prep", make_preprocessor()), ("clf", clf)])
            pipe.fit(train[FEATURES], train[TARGET])
            proba_va = pipe.predict_proba(valid[FEATURES])[:, 1]
            metrics = evaluate(valid[TARGET], proba_va, "valid")
            mlflow.log_metrics(metrics)
            results[name] = metrics["valid_auc"]
            print(f"{name}: AUC validación = {metrics['valid_auc']:.4f}")

    best_model = max(results, key=results.get)
    mlflow.log_param("best_model", best_model)

    # --- Hiperparametrización con validación cruzada walk-forward (paridad con el notebook) ---
    # Cada fold entrena con los snapshots previos del train y valida con el mes siguiente:
    # respeta la naturaleza temporal y nunca toca el backtest.
    from sklearn.model_selection import RandomizedSearchCV
    from sklearn.base import clone
    from scipy.stats import loguniform, randint

    train_months = np.sort(train["snapshot_date"].unique())
    pos = np.arange(len(train)); snap_tr = train["snapshot_date"].to_numpy()
    y_tr_arr = train[TARGET].to_numpy(); cv_folds = []
    for k in range(1, len(train_months)):
        tr_idx = pos[np.isin(snap_tr, train_months[:k])]
        va_idx = pos[snap_tr == train_months[k]]
        if len(va_idx) and y_tr_arr[va_idx].sum() > 0:
            cv_folds.append((tr_idx, va_idx))

    PARAM_SPACE = {
        "logistic_regression": {
            "clf__C": loguniform(1e-3, 1e2),
            "clf__penalty": ["l1", "l2"],
            "clf__solver": ["liblinear", "saga"]},
        "hist_gradient_boosting": {
            "clf__learning_rate": loguniform(1e-2, 3e-1),
            "clf__max_leaf_nodes": randint(15, 63),
            "clf__min_samples_leaf": randint(20, 80),
            "clf__l2_regularization": loguniform(1e-3, 1e1)},
    }
    tuning_pipe = Pipeline([("prep", make_preprocessor()),
                            ("clf", clone(MODELS[best_model]))])
    search = RandomizedSearchCV(tuning_pipe, PARAM_SPACE[best_model], n_iter=20,
                                scoring="roc_auc", cv=cv_folds, n_jobs=-1,
                                random_state=RANDOM_STATE, refit=True, error_score=0.0)
    search.fit(train[FEATURES], train[TARGET])
    auc_base = results[best_model]
    auc_tuned = roc_auc_score(valid[TARGET],
                              search.best_estimator_.predict_proba(valid[FEATURES])[:, 1])
    mlflow.log_metric("cv_auc_walkforward", search.best_score_)
    mlflow.log_metric("valid_auc_tuned", auc_tuned)
    mlflow.log_params({f"best_{k.replace('clf__','')}": v
                       for k, v in search.best_params_.items()})
    if auc_tuned + 1e-6 >= auc_base:          # adoptar solo si no empeora la validación
        MODELS[best_model] = clone(search.best_estimator_.named_steps["clf"])
        mlflow.log_param("tuning_adopted", True)
        print(f"Tuning adoptado: valid AUC {auc_base:.4f} -> {auc_tuned:.4f}")
    else:
        mlflow.log_param("tuning_adopted", False)
        print("Tuning descartado; se conserva la configuración base")

    # Reentrenar con train + validation y evaluar una sola vez en backtest
    dev = pd.concat([train, valid])
    final_pipeline = Pipeline([("prep", make_preprocessor()),
                               ("clf", MODELS[best_model])])
    final_pipeline.fit(dev[FEATURES], dev[TARGET])
    proba_bt = final_pipeline.predict_proba(backtest[FEATURES])[:, 1]
    bt_metrics = evaluate(backtest[TARGET], proba_bt, "backtest")
    bt_metrics["backtest_positive_rate"] = backtest[TARGET].mean()
    mlflow.log_metrics(bt_metrics)

    mlflow.sklearn.log_model(
        final_pipeline, "model",
        registered_model_name="olist-churn-model",
        input_example=dev[FEATURES].head(5))

print("Mejor modelo:", best_model)
print({k: round(v, 4) for k, v in bt_metrics.items()})

# COMMAND ----------

# MAGIC %md ## 6. Métricas de negocio (lift por decil)

# COMMAND ----------

bt = backtest.assign(score=proba_bt)
bt["decile"] = pd.qcut(bt.score.rank(method="first"), 10,
                       labels=range(1, 11)).astype(int)
deciles = (bt.groupby("decile")
             .agg(n=("is_repeat", "size"), repeaters=("is_repeat", "sum"),
                  repeat_rate=("is_repeat", "mean"))
             .sort_index(ascending=False))
deciles["lift"] = deciles.repeat_rate / bt.is_repeat.mean()
print(deciles)

top3 = bt[bt.decile >= 8]
captura = top3.is_repeat.sum() / bt.is_repeat.sum()
print(f"Top-30% por score captura {captura:.1%} de los recompradores")

dbutils.notebook.exit(f"OK best_model={best_model} "
                      f"backtest_auc={bt_metrics['backtest_auc']:.4f}")
