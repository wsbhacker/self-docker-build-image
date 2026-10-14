# webhook-runner：通用 webhook 接收/处理服务

镜像只是"工具箱"（adnanh/webhook + git + curl + python3），业务全部来自挂载。本目录即部署内容的源头，与 VPS 挂载点一一对应：

| 本目录 | 挂载到容器 | 内容 |
|---|---|---|
| `hooks.d/` | `/etc/webhook/hooks.d` (:ro) | 每用例一个 json：路由 id + 验签规则 + 指向脚本 |
| `scripts/` | `/hooks/scripts` (:ro) | 每用例一个 sh（宿主机 chmod +x），execute-command 的目标 |
| （用例工作目录） | 如 `/ledger` (rw) | 脚本操作的数据，如 git 仓库，按用在 compose 里加挂载 |

## 加新用例

1. `hooks.d/` 加 `xxx.json`（id=xxx；trigger-rule 做验签与分支/事件过滤）
2. `scripts/` 加 `xxx.sh` 并 chmod +x
3. compose 加该用例需要的工作目录挂载与环境变量
4. `docker restart webhook-runner`（`-hotreload` 只热重载已加载文件的内容变化，如换 secret；**新增文件必须重启**）
5. GitHub 仓库 Settings → Webhooks：`https://webhook-saas.0xw5b.top/hooks/xxx`，secret 与 json 一致，按需订阅事件

## 现有用例：ledger-sync（beancount 账本同步）

- `hooks.d/ledger-sync.json`：HMAC 验签（`payload-hmac-sha256`）+ 仅 `refs/heads/main` 的 push
- `scripts/ledger-sync.sh`：flock 防并发 → `git pull --ff-only` → 可选 `bean-check`（探测式，runner 不预装 beancount，装了就跑）→ 失败发 ntfy
- 环境变量：`LEDGER_SYNC_TOKEN`（可选，fine-grained PAT：仅账本仓库 + Contents:Read-only + 90 天过期；留空沿用仓库 remote 内嵌 token）、`NTFY_TOPIC`（可选，失败推送主题）、`NTFY_SERVER`（可选，自托管 ntfy 地址，留空用公共服 ntfy.sh；注意 iOS 对自托管只能轮询推送有延迟，Android 即时）
- 工作目录：账本仓库挂 `/ledger`（rw，pull 需写 `.git`）；fava 容器继续独立挂 `:ro` 互不影响

## 部署注意

- hooks json 含 secret：本仓库内是占位符，拷上 VPS 后改真实 secret、权限 600，真实件勿进任何 git
- 容器 uid 1000（runner）：宿主机挂载目录/仓库 owner 应为 1000（`ls -n` 确认），否则 git pull 写入失败
- 排障速查：HTTP 500 = HMAC 签名错或脚本退出非 0（`docker logs webhook-runner` 分辨两者）；200 但日志 "not satisfied" = 规则不匹配（如非 main 分支，无害，命令未执行）
- 测试投递须带 `Content-Type: application/json`，否则 payload 不解析、分支规则永远不满足（GitHub 实发总带）
