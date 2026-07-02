import os
import sys
import time
import select
import psycopg2

# 从环境变量获取配置
M_HOST = os.getenv("MASTER_HOST")
M_PORT = os.getenv("MASTER_PORT", "5432")
M_DB = os.getenv("MASTER_DB")
M_USER = os.getenv("MASTER_USER")
M_PWD = os.getenv("MASTER_PASSWORD")

S_HOST = os.getenv("SLAVE_HOST")
S_PORT = os.getenv("SLAVE_PORT", "5432")
S_DB = os.getenv("SLAVE_DB")
S_USER = os.getenv("SLAVE_USER")
S_PWD = os.getenv("SLAVE_PASSWORD")

MASTER_DSN = f"host={M_HOST} port={M_PORT} dbname={M_DB} user={M_USER} password={M_PWD}"
SLAVE_DSN = f"host={S_HOST} port={S_PORT} dbname={S_DB} user={S_USER} password={S_PWD}"

def get_connections():
    m_conn = psycopg2.connect(MASTER_DSN)
    s_conn = psycopg2.connect(SLAVE_DSN)
    m_conn.autocommit = True
    s_conn.autocommit = True
    return m_conn, s_conn

def sync_ddl_job():
    m_conn, s_conn = None, None
    try:
        m_conn, s_conn = get_connections()
        m_cur = m_conn.cursor()
        s_cur = s_conn.cursor()
        
        # 1. 查询未同步的 DDL，按 ID 顺序排列（严格保证事务顺序）
        m_cur.execute("SELECT id, command FROM ddl_log WHERE synced = FALSE ORDER BY id ASC;")
        rows = m_cur.fetchall()
        
        if rows:
            print(f"[INFO] 发现 {len(rows)} 个未同步的表结构变更，开始同步...")
            
        for row in rows:
            log_id, ddl_sql = row[0], row[1]
            print(f"[DDL EXEC] 正在从库执行: {ddl_sql.strip()}")
            
            # 2. 在从库重放建表语句
            try:
                s_cur.execute(ddl_sql)
            except psycopg2.errors.DuplicateTable:
                print(f"[WARN] 从库已存在该表，跳过创建。")
            
            # 3. 标记主库流水为已同步
            m_cur.execute("UPDATE ddl_log SET synced = TRUE WHERE id = %s;", (log_id,))
            
            # 4. 核心：通知从库的逻辑复制引擎刷新发布，将新表纳入数据流
            s_cur.execute("ALTER SUBSCRIPTION prod_sub REFRESH PUBLICATION;")
            print(f"[SUCCESS] 表 ID {log_id} 同步成功并已刷新订阅。")
            
        m_cur.close()
        s_cur.close()
    except Exception as e:
        print(f"[ERROR] 同步线程发生异常: {e}", file=sys.stderr)
    finally:
        if m_conn: m_conn.close()
        if s_conn: s_conn.close()

def main():
    print("[INIT] DDL 自动同步伴生服务启动中...")
    
    # 检查从库数据库是否就绪，以及订阅是否建立
    while True:
        try:
            s_conn = psycopg2.connect(SLAVE_DSN)
            s_cur = s_conn.cursor()
            # 检查从库是否已经建好了订阅，如果没有，提示用户先去建立初试订阅
            s_cur.execute("SELECT 1 FROM pg_subscription WHERE subname = 'prod_sub';")
            if not s_cur.fetchone():
                print("[WAIT] 检测到从库尚未建立名为 'prod_sub' 的订阅，请根据指南进行初始订阅...")
                time.sleep(10)
                continue
            s_cur.close()
            s_conn.close()
            break
        except Exception as e:
            print(f"[WAIT] 等待从库数据库响应... {e}")
            time.sleep(5)

    # 首次启动或断线重连时，先全量追平一次历史未同步的 DDL
    sync_ddl_job()

    # 进入监听主库 NOTIFY 的长连接循环
    while True:
        try:
            m_conn = psycopg2.connect(MASTER_DSN)
            m_conn.autocommit = True
            cursor = m_conn.cursor()
            cursor.execute("LISTEN ddl_update_channel;")
            print("[STATUS] 成功进入 LISTEN 状态，实时监控主库 DDL 变动...")
            
            while True:
                # 阻塞等待主库信号，每 60 秒发送一次轻量查询保活
                if select.select([m_conn], [], [], 60) == ([], [], []):
                    cursor.execute("SELECT 1;")
                else:
                    m_conn.poll()
                    while m_conn.notifies:
                        m_conn.notifies.pop(0)
                        print("[NOTIFY] 捕获到主库建表事件通知！")
                        sync_ddl_job()
        except Exception as e:
            print(f"[DISCONNECT] 与主库连接断开，10 秒后尝试重连... 错误: {e}", file=sys.stderr)
            time.sleep(10)

if __name__ == "__main__":
    main()
