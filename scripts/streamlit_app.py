"""
FSI Zero to Snowflake - Streamlit in Snowflake サンプルアプリ
============================================================
法人営業データ (corporate_sales) と貿易取引データ (trade_transactions) を
可視化するシンプルなダッシュボードです。

使い方:
  1. Snowsight → Projects → Streamlit → + Streamlit App
  2. データベース: fsi_zts_101, スキーマ: analytics, WH: fsi_analyst_wh
  3. このファイルの内容を貼り付けて Run
"""

import streamlit as st
from snowflake.snowpark.context import get_active_session

# --- セッション取得 ---
session = get_active_session()

st.set_page_config(page_title="FSI Trade Analytics", layout="wide")
st.title("FSI Zero To Snowflake - ダッシュボード")

# --- タブ構成 ---
tab1, tab2 = st.tabs(["法人営業パイプライン", "貿易取引サマリ"])

# ==============================
# Tab 1: 法人営業パイプライン
# ==============================
with tab1:
    st.header("法人営業パイプライン分析")

    # 営業担当者別サマリ
    df_rep = session.sql("""
        SELECT sales_rep, total_deals, won_deals, active_deals,
               ROUND(win_rate * 100, 1) AS win_rate_pct,
               won_amount, pipeline_amount
        FROM fsi_zts_101.analytics.sales_rep_performance_v
        ORDER BY won_amount DESC
    """).to_pandas()

    col1, col2, col3 = st.columns(3)
    col1.metric("総案件数", int(df_rep['TOTAL_DEALS'].sum()))
    col2.metric("受注件数", int(df_rep['WON_DEALS'].sum()))
    col3.metric("受注総額", f"¥{int(df_rep['WON_AMOUNT'].sum()):,}")

    st.subheader("営業担当者別パフォーマンス")
    st.dataframe(df_rep, use_container_width=True)

    # 業種×ステージ
    st.subheader("業種・ステージ別サマリ")
    df_pipeline = session.sql("""
        SELECT industry, stage, deal_count, total_amount
        FROM fsi_zts_101.analytics.sales_pipeline_summary_v
        ORDER BY industry, stage
    """).to_pandas()

    st.bar_chart(
        df_pipeline.pivot_table(index='INDUSTRY', columns='STAGE', values='DEAL_COUNT', fill_value=0)
    )

# ==============================
# Tab 2: 貿易取引サマリ
# ==============================
with tab2:
    st.header("貿易取引サマリ (日次)")

    # 拠点フィルタ
    branches = session.sql("""
        SELECT DISTINCT booking_branch FROM fsi_zts_101.analytics.daily_trade_summary_v ORDER BY 1
    """).to_pandas()['BOOKING_BRANCH'].tolist()

    selected_branch = st.selectbox("拠点を選択", ["全拠点"] + branches)

    branch_filter = ""
    if selected_branch != "全拠点":
        branch_filter = f"WHERE booking_branch = '{selected_branch}'"

    # 通貨別取引額
    st.subheader("通貨別取引額")
    df_ccy = session.sql(f"""
        SELECT currency_code, SUM(total_amount) AS total_amount, SUM(tx_count) AS tx_count
        FROM fsi_zts_101.analytics.daily_trade_summary_v
        {branch_filter}
        GROUP BY currency_code
        ORDER BY total_amount DESC
    """).to_pandas()

    col1, col2 = st.columns(2)
    with col1:
        st.dataframe(df_ccy, use_container_width=True)
    with col2:
        st.bar_chart(df_ccy.set_index('CURRENCY_CODE')['TOTAL_AMOUNT'])

    # 日次推移
    st.subheader("日次取引件数推移")
    df_daily = session.sql(f"""
        SELECT trade_date, SUM(tx_count) AS daily_tx_count
        FROM fsi_zts_101.analytics.daily_trade_summary_v
        {branch_filter}
        GROUP BY trade_date
        ORDER BY trade_date
    """).to_pandas()

    st.line_chart(df_daily.set_index('TRADE_DATE')['DAILY_TX_COUNT'])

    # 取引種別
    st.subheader("取引種別内訳")
    df_type = session.sql(f"""
        SELECT transaction_type, SUM(tx_count) AS tx_count, SUM(total_amount) AS total_amount
        FROM fsi_zts_101.analytics.daily_trade_summary_v
        {branch_filter}
        GROUP BY transaction_type
    """).to_pandas()

    st.dataframe(df_type, use_container_width=True)
