"""
FSI Zero to Snowflake - Excel ローダー (Snowpark Stored Procedure 参考実装)
============================================================================
このファイルは 02b_data_load_excel.sql 内の Python Stored Procedure
($$ ... $$) ブロックの参考実装です。IDE での開発・デバッグ用に独立ファイル
として提供しています。
※ SQL 内の SP 実装と細部が異なる場合があります (BytesIO ラップ等)。
  正式な実行は Snowflake 内の SP 経由で行ってください。

実行環境: Snowflake Snowpark (Python 3.11)
必要パッケージ: snowflake-snowpark-python, openpyxl, pandas

使い方:
  CALL fsi_zts_101.raw_excel.load_excel_to_table(
    'fsi_zts_101.raw_excel.excel_demo_stage/corporate_sales_data.xlsx',
    'fsi_zts_101.raw_excel.corporate_sales'
  );
"""

import openpyxl
import pandas as pd
from datetime import date, datetime


def main(session, stage_path: str, target_table: str) -> str:
    """
    指定された Stage パス上の Excel ファイルを読み取り、
    ターゲットテーブルに追記 (append) する。

    Parameters
    ----------
    session : snowflake.snowpark.Session
        Snowpark セッション (Stored Procedure 実行時に自動注入)
    stage_path : str
        Stage 上のファイルパス (例: 'fsi_zts_101.raw_excel.excel_demo_stage/corporate_sales_data.xlsx')
    target_table : str
        書き込み先テーブルの完全修飾名 (例: 'fsi_zts_101.raw_excel.corporate_sales')

    Returns
    -------
    str
        実行結果メッセージ
    """
    # 1. Stage 上のファイルをストリームとして読み取り
    file_stream = session.file.get_stream(f"@{stage_path}", decompress=False)

    # 2. openpyxl で Excel を読み込み
    wb = openpyxl.load_workbook(file_stream, data_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))

    if not rows:
        return "No data found in Excel file"

    # 3. ヘッダー行と データ行に分離し DataFrame 化
    header = list(rows[0])
    data_rows = rows[1:]
    df = pd.DataFrame(data_rows, columns=header)

    # 4. 日付列の型変換 (Excel の datetime → Python date)
    for col in ['last_visit_date', 'expected_close_date']:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col]).dt.date

    # 5. メタデータ列追加
    df['loaded_at'] = datetime.now()
    df['source_file'] = stage_path

    # 6. カラム名を大文字化 (Snowflake のデフォルト識別子に合わせる)
    df.columns = [c.upper() for c in df.columns]

    # 7. Snowpark DataFrame として書き込み
    snowpark_df = session.create_dataframe(df)
    snowpark_df.write.mode("append").save_as_table(target_table)

    return f"Successfully loaded {len(df)} rows from {stage_path} into {target_table}"
