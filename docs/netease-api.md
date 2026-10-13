# 网易云音乐 API 总结

参考 [missuo/kumone](https://github.com/missuo/kumone)（LGPL-3.0）的 `Sources/Kumone/Core/API/` 整理。
kumone 不依赖第三方代理服务器，直接请求网易云官方接口；本项目的实现在 `EseatenMusic/Netease/`，是独立重写的 Swift 6 代码，只沿用协议层面的常量和接口路径。

## 1. 两种请求方式

| | weapi（网页端） | eapi（PC 客户端） |
|---|---|---|
| 地址 | `POST https://music.163.com/weapi{path}` | `POST https://interface.music.163.com/eapi{path}` |
| 表单 | `params` + `encSecKey` | `params` |
| 加密 | 两层 AES-128-CBC + RSA | AES-128-ECB + MD5 摘要 |
| 用途 | 绝大多数接口 | 播放地址、下载地址、排行榜、搜索、听歌上报等 |

公共请求头：`User-Agent` 用桌面 Chrome，`Referer: https://music.163.com`，`Content-Type: application/x-www-form-urlencoded`，Cookie 里固定带 `os=pc; appver=3.1.17`。

### weapi

1. 业务参数加上 `csrf_token`（取 Cookie `__csrf`，未登录为空串）后序列化成 JSON。
2. `AES-128-CBC(json, key = "0CoJUm6Qyw8W8jud", iv = "0102030405060708")` → base64。
3. 再用 16 位随机 `secretKey` 加密一次（同一个 iv）→ base64，得到 `params`。
4. `encSecKey = RSA(reverse(secretKey))`：无填充、e = `0x10001`、模数是网页端写死的 1024 位公钥（`00e0b509f6259df8…b0a22b8e7`），结果补到 256 位十六进制。
5. 登录后 URL 上也要带 `?csrf_token=xxx`。

secretKey 可以由客户端任选，所以 kumone 和本项目都**固定一个 key，预先算好它的 encSecKey**，省掉大数运算。本项目用 `EseatenMusic2026`。

### eapi

1. 业务参数里加 `header` 字典：`os`、`appver`、`osver`、`deviceId`、`requestId`、`versioncode`、`buildver`、`resolution`、`channel`，登录后还有 `MUSIC_U`、`__csrf`。
2. `digest = md5("nobody" + apiPath + "use" + json + "md5forencrypt")`，其中 `apiPath` 是把 `/eapi` 换成 `/api` 的路径。
3. `params = HEX大写(AES-128-ECB(apiPath + "-36cd479b6b5-" + json + "-36cd479b6b5-" + digest, key = "e82ckenh8dichen8"))`。

### 响应与 Cookie

- 业务结果看响应体 `code`：200 成功，301 未登录；扫码接口用 800–803 表示状态。
- 登录态就是 Cookie `MUSIC_U` + `__csrf`，从 `Set-Cookie` 吸收、自己持久化（URLSession 自带的 Cookie 存储关掉）。
- 音频、图片地址常是 `http://`，要换成 `https://`；图片加 `?param=400y400` 取缩略图。

## 2. 接口清单

下表的路径省略了 `/weapi` 或 `/eapi` 前缀；标 🔒 的需要登录。

### 登录与账号

| 功能 | 方式 | 路径 | 关键参数 / 说明 |
|---|---|---|---|
| 二维码 key | weapi | `/login/qrcode/unikey` | `type: 1`；二维码内容 `https://music.163.com/login?codekey={unikey}` |
| 扫码状态 | weapi | `/login/qrcode/client/login` | `key, type: 1`；800 过期 · 801 等待 · 802 待确认 · 803 成功（Cookie 在 Set-Cookie） |
| 发短信验证码 | weapi | `/sms/captcha/sent` | `cellphone, ctcode, secrete: "music_middleuser_pclogin"` |
| 手机号登录 | weapi | `/w/login/cellphone` | `phone, countrycode, captcha, remember, type: "1"` |
| 续期登录 | weapi | `/login/token/refresh` | 启动时调用一次 |
| 退出登录 | weapi | `/logout` | 带着旧 Cookie 发，然后本地清掉 |
| 当前账号 | weapi | `/w/nuser/account/get` | 未登录时 `profile` 为 null |

### 用户资料库 🔒

| 功能 | 方式 | 路径 | 关键参数 / 说明 |
|---|---|---|---|
| 用户歌单 | weapi | `/user/playlist` | `uid, limit, offset, includeVideo`；`specialType == 5` 是“我喜欢的音乐” |
| 红心歌曲 id | weapi | `/song/like/get` | `uid` |
| 红心 / 取消 | weapi | `/radio/like?alg=itembased&trackId={id}&time=3` | `trackId, like` |
| 收藏的专辑 | weapi | `/album/sublist` | `limit, offset, total` |
| 收藏的艺人 | weapi | `/artist/sublist` | `limit, offset, total` |
| 最近播放 | weapi | `/play-record/song/list` | `limit`（最多 300）；按时间倒序，`list[].data` 是歌曲 |
| 听歌排行 | weapi | `/v1/play/record` | `uid, type`（1 最近一周 / 0 所有时间）；kumone 把它当“最近播放”用 |
| 云盘 | weapi | `/v1/cloud/get`、`/cloud/del` | 云盘歌曲列表 / 删除 |
| 听歌上报 | eapi | `/feedback/weblog` | `logs`；`startplay` 写入“最近播放”，`play` 累加排行，**两条都要发**；Cookie 用 `os=osx` |

### 推荐与发现

| 功能 | 方式 | 路径 | 说明 |
|---|---|---|---|
| 推荐歌单 | weapi | `/personalized/playlist` | 不需要登录 |
| 每日推荐歌单 🔒 | weapi | `/v1/discovery/recommend/resource` | |
| 每日推荐歌曲 🔒 | weapi | `/v3/discovery/recommend/songs` | 新账号 `data` 可能为 null |
| 每日推荐“不喜欢” 🔒 | weapi | `/v2/discovery/recommend/dislike` | `resId, resType: 4, sceneType: 1`，返回替换歌曲 |
| 推荐新歌 | weapi | `/personalized/newsong` | `type: "recommend", limit, areaId` |
| 私人漫游 FM 🔒 | weapi | `/v1/radio/get` | 每次几首，播完再取 |
| FM 不喜欢 🔒 | weapi | `/radio/trash/add?alg=RT&songId={id}&time=25` | |
| 心动模式 🔒 | weapi | `/playmode/intelligence/list` | `songId, playlistId, startMusicId, type: "fromPlayOne"` |
| 相似歌曲 | weapi | `/v1/discovery/simiSong` | `songid, limit` |

### 歌单

| 功能 | 方式 | 路径 | 说明 |
|---|---|---|---|
| 歌单详情 | weapi | `/v6/playlist/detail` | `id, n: 100000, s: 8`；`trackIds` 完整，`tracks` 未登录时可能不全 |
| 歌曲详情 | weapi | `/v3/song/detail` | `c: "[{\"id\":1},…]"`，用来补齐歌单缺的歌曲 |
| 歌单广场 | weapi | `/playlist/list` | `cat, order(hot/new), limit, offset` |
| 精品歌单 | weapi | `/playlist/highquality/list` | `cat, limit, lasttime`（翻页游标） |
| 排行榜 | eapi | `/toplist` | 所有官方榜单 |
| 新建 / 删除 🔒 | weapi | `/playlist/create`、`/playlist/remove` | `name, privacy(0/10), type: "NORMAL"` / `ids: "[id]"` |
| 收藏 / 取消 🔒 | weapi | `/playlist/subscribe`、`/playlist/unsubscribe` | `id`；Cookie 不能带 `os=pc`，否则返回 405“操作过于频繁” |
| 加歌 / 删歌 🔒 | weapi | `/playlist/manipulate/tracks` | `op(add/del), pid, trackIds: "[…]", imme`；**返回 512 时把 id 列表重复一遍重发** |

### 歌曲

| 功能 | 方式 | 路径 | 说明 |
|---|---|---|---|
| 播放地址 | eapi | `/song/enhance/player/url/v1` | `ids: "[…]", level, encodeType: "flac"`；`level == sky` 时加 `immerseType: "c51"`；`url` 为 null 表示无版权或需 VIP，`freeTrialInfo` 非空表示只能试听 |
| 下载地址 | eapi | `/song/enhance/download/url/v1` | `id, level, immerseType`；权限和播放地址分开判断 |
| 歌词 | weapi | `/song/lyric/v1` → `/song/lyric` | v1 多返回逐字歌词 `yrc`；拿不到再退回老接口 |

音质 `level`：`standard` · `higher` · `exhigh`（极高）· `lossless` · `hires` · `jyeffect` · `sky` · `jymaster`。

### 专辑 / 艺人

| 功能 | 方式 | 路径 | 说明 |
|---|---|---|---|
| 专辑详情 | weapi | `/v1/album/{id}` | `album` + `songs` |
| 新碟上架 | weapi | `/album/new` | `area(ALL/ZH/EA/KR/JP), limit, offset` |
| 专辑收藏状态 | eapi | `/album/detail/dynamic` | `isSub, subCount` |
| 收藏 / 取消专辑 🔒 | weapi | `/album/sub`、`/album/unsub` | `id` |
| 艺人详情 | weapi | `/v1/artist/{id}` | `artist` + 热门 50 首 `hotSongs` |
| 艺人专辑 | weapi | `/artist/albums/{id}` | `limit, offset` |
| 关注 / 取消艺人 🔒 | weapi | `/artist/sub`、`/artist/unsub` | `artistId, artistIds: "[id]"` |
| 歌手榜 | weapi | `/toplist/artist` | `type: 1`；实测忽略 `limit`，固定返回 100 位 |
| 相似艺人 🔒 | weapi | `/discovery/simiArtist` | `artistid`（实测未登录返回 301） |

### 搜索

| 功能 | 方式 | 路径 | 说明 |
|---|---|---|---|
| 搜索 | eapi | `/cloudsearch/pc` | `s, type(1 歌曲 / 10 专辑 / 100 艺人 / 1000 歌单), limit, offset` |
| 搜索建议 | weapi | `/search/suggest/web` | `s` |
| 默认关键词 | eapi | `/search/defaultkeyword/get` | 搜索框占位文字 |

## 3. 数据解析的坑

同一种对象在不同接口里字段不同，解码要宽松：

- 歌曲：新格式 `ar` / `al` / `dt`，老格式 `artists` / `album` / `duration`。
- 歌单封面：`coverImgUrl` 或 `picUrl`；播放数 `playCount` / `playcount`，有时是浮点数。
- eapi `/toplist` 返回的榜单 `tracks` 为 null（2026-10 实测），榜单前几名要打开详情才有；简介用 `description`。
- 每日推荐的 `data`、FM 的 `data` 都可能为 null。

## 4. kumone 里其他相关做法（本项目未实现）

- **CDN 双线**：音频在 `mN.music.126.net` 和 `mNc.music.126.net` 上各有一份，签名不绑主机，一个连不上就换另一个。
- **可播放判断**：结合 `privileges` 里的 `pl`、`st`、`cs`、`fee` 和用户 `vipType` 判断 VIP 专属 / 付费专辑 / 无版权 / 已下架。
- **灰色歌曲解锁**：无版权歌曲到第三方音源匹配（UnblockNeteaseMusic 思路）。

## 5. 本项目的实现

| 文件 | 内容 |
|---|---|
| `EseatenMusic/Netease/NeteaseCrypto.swift` | weapi / eapi 加密（CommonCrypto + CryptoKit） |
| `EseatenMusic/Netease/NeteaseClient.swift` | `actor`：发请求、管理并持久化 Cookie（`~/Library/Application Support/com.eseaten.music/netease-cookies.json`） |
| `EseatenMusic/Netease/NeteaseModels.swift` | 宽松解码的返回模型 |
| `EseatenMusic/Netease/NeteaseAPI.swift` | 上面清单里的全部接口 |
| `EseatenMusic/Models/Catalog.swift` | 把接口数据转换成界面用的 `Song` / `Album` / `Playlist` / `Artist` |
| `EseatenMusic/Models/Account.swift` | 登录状态和侧边栏歌单 |
| `EseatenMusic/Models/Player.swift` | AVPlayer 播放，自动跳过放不了的歌，私人漫游续播 |

界面已接入（侧边栏结构参考 kumone）：推荐（榜单、推荐歌单、新歌）、精选（新碟、热门 / 精品歌单）、漫游（私人漫游、排行榜）、搜索、专辑 / 歌单 / 艺人详情、扫码登录；登录后的“我的”：我喜欢的音乐、每日推荐、最近播放、我的收藏（专辑 / 歌手）、音乐云盘，以及创建（可新建、删除）/ 收藏（可取消收藏）的歌单。

已实现但界面暂未使用的接口：短信登录、红心、每日推荐“不喜欢”、歌单增删改、收藏专辑 / 艺人、歌词、听歌上报、心动模式、相似歌曲 / 艺人、歌手榜、云盘、下载地址、搜索建议。

2026-10-12 登录后实测通过：账号、用户歌单、红心 id、收藏的专辑和歌手、听歌排行、最近播放、云盘、每日推荐歌曲和歌单、私人漫游、相似艺人。

2026-10-12 未登录实测通过：推荐歌单、排行榜、搜索、歌单 / 专辑 / 艺人详情、歌曲详情、播放地址（VIP 歌曲返回 null 或试听片段）、歌词、新碟、歌单广场、精品歌单、歌手榜、搜索建议、默认关键词、二维码 key 与状态查询。写操作（红心、歌单增删改、收藏、听歌上报）没有实测。
