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

## 现有用例：beancount-sync（beancount 账本同步）

- `hooks.d/beancount-sync.json`：HMAC 验签（`payload-hmac-sha256`）+ 仅 `refs/heads/main` 的 push
- `scripts/beancount-sync.sh`：flock 防并发 → `git pull --ff-only` → 可选 `bean-check`（探测式，runner 不预装 beancount，装了就跑）→ 失败发 ntfy
- 环境变量：`LEDGER_SYNC_TOKEN`（可选，fine-grained PAT：仅账本仓库 + Contents:Read-only + 90 天过期；留空沿用仓库 remote 内嵌 token）、`NTFY_TOPIC`（可选，失败推送主题）、`NTFY_SERVER`（可选，自托管 ntfy 地址，留空用公共服 ntfy.sh；注意 iOS 对自托管只能轮询推送有延迟，Android 即时）
- 工作目录：账本仓库挂 `/ledger`（rw，pull 需写 `.git`）；fava 容器继续独立挂 `:ro` 互不影响
- GitHub 仓库 Settings → Webhooks：`https://webhook-saas.0xw5b.top/hooks/beancount-sync`，secret 与 json 一致，仅订阅 push

## 现有用例：wecom-notify（GitHub push → 企业微信应用消息）

- `hooks.d/wecom-notify.json`：HMAC 验签 + 仅 `refs/heads/main` 的 push（要全分支通知就删掉 ref 那条 value 规则）；`pass-arguments-to-command` 从 payload 取 pusher/仓库全名/ref/commits 数组/最新提交信息/compare 链接传给脚本——注意引擎不支持 gjson 的 `commits.#` 计数（实测 2.8.3 传空串），故传整个数组由脚本数
- `scripts/wecom-notify.sh`：拼文本消息 → gettoken 取 access_token（缓存 `/tmp/<前缀>.token` 复用、剩 300s 提前换新，遇 40014/42001 失效竞态自动重取重发一次）→ POST 应用消息接口 message/send；curl 报错或返回体 `errcode != 0` 都按失败处理
- 走的是**自建应用**消息接口（发到成员的企业微信，手机收推送），不是群机器人（机器人只要一个 URL key，但只能发群、限 20 条/分钟）
- **一机多应用约定**：hook json 经 `pass-environment-to-command` 传 `WECOM_APP_KEY=<hook id>`（前缀开关，本身不参与回落），所有 `WECOM_*` 配置变量逐个先取 `<id转大写下划线>_` 同名前缀变量、空则回落不带前缀的默认值——如 id `wecom-notify-ci` 用 `WECOM_NOTIFY_CI_WECOM_CORP_ID/_CORP_SECRET/_AGENT_ID`（可选 `_WECOM_TO_USER`）。加第二个应用 = 拷一份 hook json 改 id/secret/APP_KEY + `.env` 加前缀三件套，脚本复用不用拷；access_token 缓存按前缀隔离（token 跟 secret 走，多应用共享缓存文件会 40014 互踩）
- 环境变量：`WECOM_CORP_ID` / `WECOM_CORP_SECRET` / `WECOM_AGENT_ID`（**必填**，管理后台-应用管理-自建应用；Secret 是凭据放 VPS 侧 `.env` 勿进 git，未配置则触发即失败）；`WECOM_TO_USER`（可选，接收人 userid 多个用 `|` 分隔，默认 `@all`）；`NTFY_TOPIC`/`NTFY_SERVER`（可选，与 beancount-sync 共用做失败兜底——脚本失败时 delivery 不标红，ntfy 是唯一推送告警）
- 接收人必须在自建应用的**可见范围**内，否则 @all 发不到人（管理后台-应用管理-自建应用-可见范围）
- GitHub 仓库 Settings → Webhooks：`https://webhook-saas.0xw5b.top/hooks/wecom-notify`，secret 与 json 一致，仅订阅 push

## 现有用例：wecom-send（通用企微发送器，任意来源 → 企业微信应用消息）

- 与 wecom-notify 的分工：**不做任何消息拼凑，只接受规范信息并发送**——任何系统 `curl -d '{"title":"构建失败","content":"..."}' https://webhook-saas.0xw5b.top/hooks/wecom-send` 即可发企微消息；GitHub push 那种拼消息的活留给 wecom-notify
- `scripts/wecom-send.sh` 接口约定（与 hook json 的 `pass-arguments-to-command` 数组顺序一一对应）：`$1`=content（必填，消息全文）、`$2`=title（可选，拼正文开头【title】，兼作 ntfy 兜底标题）、`$3`=to_user（可选，覆盖默认接收人）
- **字段名适配在 json 层完成**：`pass-arguments-to-command` 里的 `name` 只是从 payload 取值的 gjson 路径，与脚本参数无名字绑定——第三方传 `title+text`/`subject+body` 都行，json 里 `name` 写第三方字段名、顺序对准 `$1/$2/$3` 序位即完成适配，脚本零改动
- `hooks.d/wecom-send.json` 是自配模板：门禁（trigger-rule）按来源自由定，模板带 HMAC 验签示例（内网信任也可删掉，但注意=任何能打到 9000 端口者都能借你的企微发消息）；要多应用隔离就照 wecom-notify.json 抄 `pass-environment-to-command` 传 `WECOM_APP_KEY`
- 环境变量与一机多应用、token 缓存、40014 重发、ntfy 失败兜底均与 wecom-notify 同款（两脚本这段逻辑是复制的，改一处请同步另一处）

## 部署注意

- hooks json 含 secret：本仓库内是占位符，拷上 VPS 后改真实 secret、权限 600，真实件勿进任何 git
- 容器 uid 1000（runner）：宿主机挂载目录/仓库 owner 应为 1000（`ls -n` 确认），否则 git pull 写入失败
- 排障速查：HTTP 500 = HMAC 签名错/规则评估错；**脚本退出非 0 时仍是 200**（实测 2.8.3，GitHub delivery 绿勾），真失败信号是 `docker logs webhook-runner` 里的 "error occurred" 行（配了 NTFY_TOPIC 才有推送兜底）；200 但日志 "not satisfied" = 规则不匹配（如非 main 分支，无害，命令未执行）
- 测试投递须带 `Content-Type: application/json`，否则 payload 不解析、分支规则永远不满足（GitHub 实发总带）
