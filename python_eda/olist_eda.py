"""
Olist E-Commerce Sales Analysis
Tools: Python, Pandas, NumPy

Expected input:
Place the nine Olist CSV files in a folder named Dataset beside this script,
or place this script in the same folder as the CSV files.

Outputs:
Creates an analysis_output folder containing data-quality summaries and
CSV summaries used for the project.
"""

from pathlib import Path
import pandas as pd
import numpy as np

# Locate the dataset folder.
SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR = SCRIPT_DIR / "Dataset"
if not DATA_DIR.exists():
    DATA_DIR = SCRIPT_DIR

OUTPUT_DIR = SCRIPT_DIR / "analysis_output"
OUTPUT_DIR.mkdir(exist_ok=True)

FILES = {
    "customers": "olist_customers_dataset.csv",
    "orders": "olist_orders_dataset.csv",
    "order_items": "olist_order_items_dataset.csv",
    "payments": "olist_order_payments_dataset.csv",
    "reviews": "olist_order_reviews_dataset.csv",
    "products": "olist_products_dataset.csv",
    "sellers": "olist_sellers_dataset.csv",
    "geolocation": "olist_geolocation_dataset.csv",
    "category_translation": "product_category_name_translation.csv",
}


def load_csv(filename):
    """Load a CSV file and raise a clear error if it is missing."""
    file_path = DATA_DIR / filename
    if not file_path.exists():
        raise FileNotFoundError(
            f"Missing file: {file_path}\n"
            "Put the Olist CSV files in a folder named 'Dataset' "
            "beside this Python script."
        )
    return pd.read_csv(file_path)


def main():
    print("Loading Olist datasets...")

    # Geolocation is a large file and is not required for the analyses below.
    data = {
        name: load_csv(filename)
        for name, filename in FILES.items()
        if name != "geolocation"
    }

    customers = data["customers"]
    orders = data["orders"]
    order_items = data["order_items"]
    payments = data["payments"]
    reviews = data["reviews"]
    products = data["products"]
    sellers = data["sellers"]
    category_translation = data["category_translation"]

    # 1. Dataset overview and data-quality report.
    overview_rows = []
    for name, df in data.items():
        overview_rows.append({
            "dataset": name,
            "rows": df.shape[0],
            "columns": df.shape[1],
            "duplicate_rows": int(df.duplicated().sum()),
            "missing_cells": int(df.isna().sum().sum()),
        })

    overview = pd.DataFrame(overview_rows)
    overview.to_csv(OUTPUT_DIR / "dataset_overview.csv", index=False)

    # 2. Convert order timestamps to datetime.
    date_columns = [
        "order_purchase_timestamp",
        "order_approved_at",
        "order_delivered_carrier_date",
        "order_delivered_customer_date",
        "order_estimated_delivery_date",
    ]
    for column in date_columns:
        if column in orders.columns:
            orders[column] = pd.to_datetime(orders[column], errors="coerce")

    # 3. Prepare delivered orders and product-level data.
    delivered_orders = orders.loc[
        orders["order_status"].eq("delivered")
    ].copy()

    order_sales = order_items.merge(
        delivered_orders[["order_id", "customer_id", "order_purchase_timestamp"]],
        on="order_id",
        how="inner",
    )

    product_sales = order_sales.merge(
        products[["product_id", "product_category_name"]],
        on="product_id",
        how="left",
    )

    product_sales = product_sales.merge(
        category_translation,
        on="product_category_name",
        how="left",
    )

    product_sales["product_category"] = (
        product_sales["product_category_name_english"]
        .fillna(product_sales["product_category_name"])
        .fillna("Unknown")
    )

    # 4. Monthly revenue (product price; freight excluded).
    product_sales["order_month"] = (
        product_sales["order_purchase_timestamp"].dt.to_period("M").astype(str)
    )
    monthly_revenue = (
        product_sales.groupby("order_month", as_index=False)
        .agg(
            revenue=("price", "sum"),
            delivered_orders=("order_id", "nunique"),
        )
        .sort_values("order_month")
    )
    monthly_revenue["revenue"] = monthly_revenue["revenue"].round(2)
    monthly_revenue.to_csv(OUTPUT_DIR / "monthly_revenue.csv", index=False)

    # 5. Revenue by product category.
    category_revenue = (
        product_sales.groupby("product_category", as_index=False)
        .agg(
            revenue=("price", "sum"),
            items_sold=("order_item_id", "count"),
            orders=("order_id", "nunique"),
        )
        .sort_values("revenue", ascending=False)
    )
    category_revenue["revenue"] = category_revenue["revenue"].round(2)
    category_revenue.to_csv(OUTPUT_DIR / "category_revenue.csv", index=False)

    # 6. Payment method distribution.
    payment_summary = (
        payments.groupby("payment_type", as_index=False)
        .agg(
            payment_records=("payment_type", "size"),
            total_payment_value=("payment_value", "sum"),
        )
        .sort_values("total_payment_value", ascending=False)
    )
    payment_summary["total_payment_value"] = (
        payment_summary["total_payment_value"].round(2)
    )
    payment_summary.to_csv(OUTPUT_DIR / "payment_method_summary.csv", index=False)

    # 7. Delivery performance.
    delivery = delivered_orders.dropna(
        subset=["order_delivered_customer_date", "order_estimated_delivery_date"]
    ).copy()
    delivery["delivery_days"] = (
        delivery["order_delivered_customer_date"]
        - delivery["order_purchase_timestamp"]
    ).dt.total_seconds() / 86400
    delivery["is_late"] = (
        delivery["order_delivered_customer_date"]
        > delivery["order_estimated_delivery_date"]
    )
    delivery_summary = pd.DataFrame([{
        "delivered_orders": len(delivery),
        "average_delivery_days": round(delivery["delivery_days"].mean(), 2),
        "late_deliveries": int(delivery["is_late"].sum()),
        "late_delivery_percentage": round(delivery["is_late"].mean() * 100, 2),
    }])
    delivery_summary.to_csv(OUTPUT_DIR / "delivery_performance.csv", index=False)

    # 8. Customer review score distribution.
    review_summary = (
        reviews.groupby("review_score", as_index=False)
        .size()
        .rename(columns={"size": "review_count"})
        .sort_values("review_score")
    )
    review_summary.to_csv(OUTPUT_DIR / "review_score_distribution.csv", index=False)

    # 9. Print key results.
    total_revenue = product_sales["price"].sum()
    total_delivered_orders = delivered_orders["order_id"].nunique()
    unique_customers = delivered_orders["customer_id"].nunique()
    average_order_value = (
        product_sales.groupby("order_id")["price"].sum().mean()
    )

    print("\nPROJECT KPI SUMMARY")
    print(f"Delivered orders: {total_delivered_orders:,}")
    print(f"Product revenue (freight excluded): R${total_revenue:,.2f}")
    print(f"Unique customers: {unique_customers:,}")
    print(f"Average order value: R${average_order_value:,.2f}")

    print("\nTop 10 product categories by revenue:")
    print(category_revenue.head(10).to_string(index=False))

    print(f"\nAnalysis files saved in: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
