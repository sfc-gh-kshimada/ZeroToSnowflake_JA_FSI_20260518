"""
FSI Zero to Snowflake - Cortex AI デモアプリ (Streamlit in Snowflake)
====================================================================
Section 5 (Cortex AI) の主要機能をインタラクティブに体験するデモアプリです。

使い方:
  1. Snowsight → プロジェクト → Streamlit → + Streamlit App
  2. データベース: fsi_zts_101, スキーマ: semantic_layer, WH: fsi_cortex_wh
  3. このファイルの内容を貼り付けて Run

"""

import streamlit as st
from snowflake.snowpark.context import get_active_session

session = get_active_session()

# --- ページ設定 ---
st.set_page_config(page_title="FSI Cortex AI Demo", layout="wide")
st.title("🏦 FSI Cortex AI デモ")
st.caption("Snowflake Cortex AI を金融取引データに適用するインタラクティブデモ")

# --- タブ構成 ---
tab1, tab2, tab3, tab4 = st.tabs([
    "🏷️ AI_CLASSIFY",
    "😊 AI_SENTIMENT",
    "🤖 AI_COMPLETE",
    "🔍 Cortex Search"
])


# ==============================
# Tab 1: AI_CLASSIFY
# ==============================
with tab1:
    st.header("AI_CLASSIFY — 取引コメントの自動分類")
    st.markdown("""
    取引コメント (`free_text_notes`) を 5 カテゴリに自動分類します。
    - **Standard**: 通常取引
    - **Urgent/Expedited**: 緊急対応
    - **Suspicious/Compliance**: コンプライアンス懸念
    - **Dispute**: 紛争・異議
    - **VIP/Priority**: VIP 対応
    """)

    sample_size = st.slider("サンプル件数", 5, 50, 10, key="classify_sample")

    if st.button("分類を実行", key="btn_classify"):
        with st.spinner("AI_CLASSIFY 実行中..."):
            df = session.sql(f"""
                SELECT
                    transaction_id,
                    free_text_notes,
                    AI_CLASSIFY(
                        free_text_notes,
                        ['Standard', 'Urgent/Expedited', 'Suspicious/Compliance', 'Dispute', 'VIP/Priority']
                    ):labels[0]::VARCHAR AS classification
                FROM fsi_zts_101.raw_trade.trade_transactions
                LIMIT {sample_size}
            """).to_pandas()
            st.dataframe(df, use_container_width=True)

            # 分布チャート
            if not df.empty:
                st.subheader("分類分布")
                chart_data = df['CLASSIFICATION'].value_counts().reset_index()
                chart_data.columns = ['分類', '件数']
                st.bar_chart(chart_data.set_index('分類'))


# ==============================
# Tab 2: AI_SENTIMENT
# ==============================
with tab2:
    st.header("AI_SENTIMENT — センチメント分析")
    st.markdown("""
    取引コメントの感情を分析します。
    - **positive**: ポジティブ (VIP 対応、問題なし)
    - **negative**: ネガティブ (コンプライアンス懸念、紛争)
    - **neutral**: ニュートラル (通常処理)
    - **mixed**: 混合
    """)

    sample_size_sent = st.slider("サンプル件数", 5, 30, 10, key="sentiment_sample")

    if st.button("センチメント分析を実行", key="btn_sentiment"):
        with st.spinner("AI_SENTIMENT 実行中..."):
            df = session.sql(f"""
                SELECT
                    transaction_id,
                    free_text_notes,
                    AI_SENTIMENT(free_text_notes):categories[0]:sentiment::VARCHAR AS sentiment
                FROM fsi_zts_101.raw_trade.trade_transactions
                LIMIT {sample_size_sent}
            """).to_pandas()
            st.dataframe(df, use_container_width=True)

            if not df.empty:
                st.subheader("センチメント分布")
                chart_data = df['SENTIMENT'].value_counts().reset_index()
                chart_data.columns = ['センチメント', '件数']
                # 色分け
                st.bar_chart(chart_data.set_index('センチメント'))


# ==============================
# Tab 3: AI_COMPLETE
# ==============================
with tab3:
    st.header("AI_COMPLETE — LLM によるコンプライアンスリスク判定")
    st.markdown("取引コメントを LLM に分析させ、リスクレベルを判定します。")

    # カスタムプロンプト or プリセット
    mode = st.radio("モード", ["取引コメントのリスク判定", "カスタムプロンプト"], key="complete_mode")

    if mode == "取引コメントのリスク判定":
        num_records = st.slider("分析件数", 1, 5, 3, key="complete_records")

        if st.button("リスク判定を実行", key="btn_complete_risk"):
            with st.spinner("AI_COMPLETE (claude-sonnet-4-6) 実行中..."):
                df = session.sql(f"""
                    SELECT
                        transaction_id,
                        free_text_notes,
                        AI_COMPLETE(
                            'claude-sonnet-4-6',
                            'あなたは金融機関のコンプライアンス審査官です。' ||
                            '以下の取引コメントを分析し、リスクレベルを HIGH / MEDIUM / LOW で判定し、' ||
                            '理由を1文で述べてください。回答は日本語で。' ||
                            CHR(10) || CHR(10) || '取引コメント: ' || free_text_notes
                        ) AS compliance_assessment
                    FROM fsi_zts_101.raw_trade.trade_transactions
                    LIMIT {num_records}
                """).to_pandas()

                for _, row in df.iterrows():
                    with st.expander(f"📋 {row['TRANSACTION_ID']} — {row['FREE_TEXT_NOTES'][:60]}..."):
                        st.markdown(f"**取引コメント:** {row['FREE_TEXT_NOTES']}")
                        st.markdown(f"**AI 判定結果:**")
                        st.info(row['COMPLIANCE_ASSESSMENT'])

    else:  # カスタムプロンプト
        custom_prompt = st.text_area(
            "プロンプトを入力",
            value="Snowflake Cortex AI を金融業界で活用する主なユースケースを3つ挙げてください。",
            height=100,
            key="custom_prompt"
        )

        if st.button("送信", key="btn_complete_custom"):
            with st.spinner("AI_COMPLETE 実行中..."):
                result = session.sql(f"""
                    SELECT AI_COMPLETE('claude-sonnet-4-6', '{custom_prompt.replace("'", "''")}') AS response
                """).to_pandas()
                st.markdown("### AI の回答:")
                st.write(result['RESPONSE'][0])


# ==============================
# Tab 4: Cortex Search
# ==============================
with tab4:
    st.header("🔍 Cortex Search — セマンティック検索")
    st.markdown("""
    取引コメントを**意味ベース**で検索します。キーワード完全一致ではなく、
    テキストの意味的な類似性に基づいてランキングされます。

    **前提:** Section 5 で `harmonized.trade_notes_search` を作成済み
    """)

    search_query = st.text_input(
        "検索クエリ (自然言語で入力)",
        value="suspicious compliance review",
        key="search_query"
    )
    search_limit = st.slider("結果件数", 3, 20, 5, key="search_limit")

    if st.button("検索", key="btn_search"):
        with st.spinner("Cortex Search 実行中..."):
            try:
                df = session.sql(f"""
                    SELECT
                        results.value:transaction_id::VARCHAR   AS transaction_id,
                        results.value:free_text_notes::VARCHAR  AS free_text_notes,
                        results.value:transaction_type::VARCHAR AS transaction_type,
                        results.value:booking_branch::VARCHAR   AS booking_branch,
                        TRY_TO_DECIMAL(results.value:amount::VARCHAR, 18, 2) AS amount
                    FROM TABLE(
                        FLATTEN(
                            PARSE_JSON(
                                SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                                    'fsi_zts_101.harmonized.trade_notes_search',
                                    '{{"query": "{search_query.replace('"', '\\"')}", "columns": ["transaction_id", "free_text_notes", "transaction_type", "booking_branch", "amount"], "limit": {search_limit}}}'
                                )
                            ):results
                        )
                    ) AS results
                """).to_pandas()

                if df.empty:
                    st.warning("検索結果が 0 件です。別のクエリを試してください。")
                else:
                    st.success(f"{len(df)} 件の関連取引が見つかりました")
                    st.dataframe(df, use_container_width=True)
            except Exception as e:
                st.error(f"Cortex Search エラー: {str(e)[:300]}")
                st.info("Cortex Search Service が未作成の可能性があります。Section 5 を先に実行してください。")


# --- フッター ---
st.divider()
st.caption("FSI Zero to Snowflake ハンズオン | Cortex AI デモアプリ | データはすべて合成データです")
