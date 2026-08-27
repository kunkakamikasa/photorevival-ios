# PhotoRevive CMS 与业务接口契约

实现基线：`AIVideoAiApiCms` 的 `codex/photorevive-cms-backend` 分支，
2026-08-24。本文中的接口和字段已在代码中实现，部署后生效。

## 1. `get-app-carousels` 优惠券内容结构

现有模板轮播结构保持不变。新增字段：

- `content_kind`: `template`（默认）或 `coupon`
- `placement`: `hero`（默认）或 `bottom_banner`
- `target_kind`: `none`、`try_now` 或 `fixed_feature`
- `target_fixed_feature_key`: `target_kind=fixed_feature` 时必填，绑定固定功能模板库
- `coupon`: 仅 `content_kind=coupon` 时必填

首页第一张优惠券和底部横幅都使用同一数据结构。App 只接受周订阅和年订阅各一项；商品 ID、价格文案、周期文案、日均价格和积分说明均由 CMS 返回。

```json
{
  "items": [
    {
      "id": "uuid",
      "page": "home",
      "title": "Summer offer",
      "content_kind": "coupon",
      "placement": "hero",
      "cover_type": "image",
      "cover_image_url": "https://cdn.example.com/home-offer.jpg",
      "sort_order": 0,
      "target_section_id": null,
      "target_filter_id": null,
      "coupon": {
        "headline": "Congratulations",
        "subtitle": "You've got a Special gift!",
        "discount_text": "SAVE 65%",
        "artwork_image_url": "https://cdn.example.com/coupon-artwork.png",
        "weekly": {
          "product_id": "special_gift_weekly",
          "title": "Weekly Plan",
          "price_text": "$9.99",
          "period_text": "/week",
          "daily_price_text": "$1.43",
          "credits_text": "400 per week"
        },
        "annual": {
          "product_id": "special_gift_yearly",
          "title": "Annual Plan",
          "price_text": "$39.99",
          "period_text": "/year",
          "daily_price_text": "$0.11",
          "credits_text": "400 per week"
        }
      }
    }
  ]
}
```

后端/CMS 已实现的校验：

- `page=home, placement=hero, content_kind=coupon` 最多一条启用记录，并固定在第一位。
- `placement=bottom_banner` 仅允许 `page=home`，最多一条启用记录。
- 两个 `product_id`、`cover_image_url`、全部价格显示字段必填。
- `content_kind=template` 时沿用现有成对的模板/滤镜目标校验。
- `content_kind=coupon` 时模板/滤镜目标必须为空。
- App 已兼容旧响应；未返回新字段的记录按 `template + hero` 处理。

## 2. 已可直接使用的接口

| 场景 | 接口 | 结论 |
|---|---|---|
| 当前积分 | `GET /user-status` | 满足，使用 `credits_balance` |
| 积分流水/分桶 | `GET /credit-transactions` | 满足，支持 recurring/lifetime 与筛选 |
| 签到配置与状态 | `GET /daily-checkin-status` | 满足，启用状态和每日奖励均服务端配置 |
| 签到领取 | `POST /daily-checkin-sign` | 满足，服务端幂等发放 |
| 奖励任务 | `GET /reward-tasks-status`、`POST /claim-reward-task` | 满足任务开关、奖励值、重复策略与幂等领取 |
| 邀请码和奖励 | `GET /referral-status`、`POST /redeem-referral` | 满足手动邀请码兑换和服务端奖励归因 |
| 历史删除/取消 | `POST /delete-task`、`POST /cancel-task` | 满足 |
| AI Photo CMS 顶图 | `GET /get-app-carousels?page=photo` | 满足；App 使用 CMS 图片，并按 `target_kind` 进入 Try Now 或固定功能 |
| AI Video 四模式素材 | `GET /get-app-fixed-features` | 满足；功能顺序和入口固定，只读取四张/四段 CMS 素材 |

## 3. 本次后端处理结果

### 已完成

1. 保留 `list-tasks` 原有最近两小时机制；新增仅供本 App 使用的
   `GET /photorevive-history`。新接口固定按当前用户和
   `app_id=photorevival` 隔离、无两小时上限、使用 cursor 分页。
2. 新增认证接口 `POST /bind-app-context`，OAuth 登录完成及恢复旧 session
   时可靠写入 `user_metadata.app_id=photorevival`，App 随后刷新 session。
3. 优惠券型轮播和底部横幅已扩展到数据库、管理后台 RPC/页面和
   `get-app-carousels`，结构及校验见第 1 节。
4. 固定功能配置新增 CMS item 绑定。`get-app-fixed-features` 返回稳定的
   `generation_target`（含 `item_id`、scene、model、积分和生成 endpoint），
   无需再增加一套专用生成接口。
5. 新增 CMS 应用级 `credit_pricing`。客户端与生成接口共用该配置：Restore
   35、视频增强每秒 10、图/文生视频按时长/分辨率/声音/多镜头组合计价、
   其他视频 60、图片生成统一 30。所有展示声音、多镜头、时长和分辨率设置的
   Image/Text to Video 模板与滤镜均使用相同的动态组合计价；60 分仅用于没有
   这组输出设置的其他视频能力。
6. `photorevive-history` 为视频返回 Cloudinary 第 0 秒 JPG
   `thumbnail_url`；App 列表只加载封面，点击后才播放结果视频。
7. `upload-image` 以 `image_url` 为规范字段，同时返回相同值的 `url`
   兼容别名；客户端按 `image_url ?? url` 读取。
8. 邀请按本版产品决定只保留手动邀请码，继续复用 `referral-status` 和
   `redeem-referral`，未增加 Deep Link 自动归因。

### 后续非阻塞建议

1. 奖励任务中的 `client_evidence` 只能证明客户端提交过 JSON，不能证明
   真正关注社媒或完成分享。高价值任务应改为 `server_verified`，并由可信
   回调/RPC 解锁。
2. 建议明确生成接口所有状态枚举、最大轮询时长和任务超时状态；当前文档
   主要描述 processing/completed/failed。
3. 建议增加积分一致性自动测试：
   `user-status.credits_balance == recurring_balance + lifetime_balance`。

## 4. 生成流程适配结论

CMS 模板的通用流程接口基本齐全：图片上传后可调用 `image-to-image` / `image-to-video`，纯文本可调用 `text-to-image` / `text-to-video`，视频增强可用直传接口配合 `video-enhance`，异步视频可通过 `get-task` 轮询。

固定功能到生成配置的稳定映射及长期历史接口现已具备。客户端应使用
`generation_target.endpoint + item_id` 接通通用生成链路，并以
`photorevive-history` 作为作品库数据源；数据库迁移与 Edge Functions 部署后，
接口集合可以替换相应的本地假数据链路。

## 5. 模板列表展示配置

`get-feature-configs.sections[]` 由 CMS 返回三个模板级展示字段：

- `badge`: `AUTO` / `HOT` / `NEW` / `OFF`。`AUTO` 表示当前可见列表第 1 个模板显示 HOT、第 2 个显示 NEW；其余值为显式覆盖。
- `show_prompt`: 布尔值，统一控制同一模板下所有滤镜的上传页是否展示提示词，与单个滤镜的 `prompt_template` 是否为空无关。
- `prompt_editable`: 布尔值，仅在 `show_prompt=true` 时生效；`false` 为只读展示，`true` 允许用户修改。缺省按 `false` 处理，以兼容旧模板。

列表卡片不使用单滤镜角标；模板列表只展示 section 级 `badge`。

图片类 `material_requirements[]` 的 `image_count` 决定上传位数量，客户端支持
1–3 个上传位。`cover_images[]` 按数组顺序对应 `Image1`、`Image2`、`Image3`
的可选占位图；数组缺失或某一位没有图片时，客户端显示默认的“Upload Image”
样式。提示词正文中的 `@Image1`、`@Image2`、`@Image3` 保持原文提交，但在上传
页以圆角引用标签渲染。
