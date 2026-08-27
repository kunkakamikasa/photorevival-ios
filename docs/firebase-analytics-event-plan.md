# Firebase Analytics 埋点方案

## 原则

- 优先使用 Firebase 推荐事件：`screen_view`、`tutorial_begin`、`tutorial_complete`、`login`、`select_content`、`begin_checkout`。
- 自定义事件统一采用小写 snake_case，参数保持低基数。
- 不上传邮箱、提示词、用户图片或视频 URL、服务端 task ID、完整错误消息。
- 当前购买链路使用 StoreKit 2。验证成功后调用 `Analytics.logTransaction` 交给 Firebase 生成 IAP 收入事件；业务代码不再额外记录 `purchase`，避免收入重复计算。
- `first_open`、`app_open`、`session_start` 等生命周期事件由 Firebase 自动采集。
- 当前 App 明确启用 Analytics collection；若以后增加独立的数据分析同意开关，应由该开关控制 collection 状态。

## 事件字典

| 漏斗 | 事件 | 触发点 | 关键参数 |
| --- | --- | --- | --- |
| 页面 | `screen_view` | 首页 Tab、登录页等关键页面出现 | `screen_name`, `screen_class` |
| 引导 | `tutorial_begin` | 首个引导页出现 | — |
| 引导 | `onboarding_step_view` | 每个引导步骤出现 | `step_name`, `step_index` |
| 引导 | `tutorial_complete` | 用户完成最后一个引导步骤 | — |
| 登录 | `auth_gate_view` | 受限操作触发登录页 | `source` |
| 登录 | `auth_attempt` | 点击 Apple/Google 登录 | `method` |
| 登录 | `auth_result` | 登录完成、取消或失败 | `method`, `result`, `failure_type` |
| 登录 | `login` | 登录成功 | `method` |
| 模板 | `select_content` | 点击模板或固定功能入口 | `content_type`, `item_id`, `source` |
| 模板 | `template_detail_view` | 模板详情出现或上下切换 | `content_type`, `item_id`, `input_count`, `model_type` |
| 模板 | `template_try_now` | 点击 Try Now | `content_type`, `item_id`, `input_count`, `model_type` |
| 生成 | `generation_blocked` | 参数、素材或余额校验未通过 | `content_type`, `item_id`, `reason` |
| 生成 | `generation_start` | 生成参数校验通过，准备上传 | `content_type`, `item_id`, `credits_cost`, `input_count`, `resolution`, `duration_seconds`, `sound_enabled`, `multi_shot_enabled` |
| 生成 | `generation_submitted` | 服务端接受任务 | `content_type`, `item_id` |
| 生成 | `generation_complete` | 服务端任务完成 | `content_type`, `item_id`, `elapsed_ms` |
| 生成 | `generation_failed` | 上传、提交、轮询或服务端失败 | `content_type`, `item_id`, `stage`, `failure_type`, `elapsed_ms` |
| 结果 | `content_saved` | 用户保存生成结果 | `content_type`, `item_id` |
| 促销 | `paywall_view` | 付费墙或优惠页出现，用于页面级漏斗 | `paywall_variant`, `source`, `product_id` 及全部促销属性 |
| 促销 | `view_promotion` | 促销页/促销素材曝光 | `promotion_id`, `promotion_name`, `creative_name`, `creative_slot`, `offer_variant`, `billing_period`, `product_id`, `items` |
| 促销 | `select_promotion` | 用户点击促销页购买 CTA；即使商品查询失败也记录 | `promotion_id`, `promotion_name`, `creative_name`, `creative_slot`, `offer_variant`, `billing_period`, `product_id`, `items` |
| 订阅 | `begin_checkout` | 获取到 StoreKit 商品并准备调起购买 | `product_id`, `currency`, `value`, `items` 及全部促销属性 |
| 订阅 | `subscription_result` | 购买完成、取消、等待或失败 | `product_id`, `result`, `failure_stage`, `currency`, `value` 及全部促销属性 |
| 订阅 | `restore_purchase` | 恢复购买开始及结果 | `result`, `failure_stage` |

当前图片生成界面仍是本地预览流程，因此只记录 `generation_start`，不伪造服务端 `generation_submitted` 或 `generation_complete`；接入图片生成 API 后再补齐后两项。

## 促销收益归因设计

采用“统一事件 + 促销维度”，不为每张促销页创建不同事件名。这样 Firebase 能直接用一套漏斗横向比较所有促销，新增促销也只需要新增一组属性值。

| 属性 | 含义 | 示例 |
| --- | --- | --- |
| `promotion_id` | 稳定且唯一的促销活动/页面标识；不要随文案调整而变化 | `limited_time_offer`, `returning_family` |
| `promotion_name` | 促销大类，便于汇总同系列页面 | `membership`, `returning_offer`, `summer_sale` |
| `creative_name` | 当前创意或视觉版本 | `limited_time_popup`, `super_prize_ticket` |
| `creative_slot` | 促销入口/展示位置 | `onboarding`, `home_membership`, `membership_follow_up` |
| `offer_variant` | 具体优惠或套餐版本 | `pro`, `proPlus`, `summer_sale_annual` |
| `billing_period` | 计费周期 | `weekly`, `annual` |
| `product_id` | App Store Connect Product ID；实际售卖 SKU | `limited_time_offer_yearly` |
| `value`, `currency` | 结账时为 Product 展示价格；购买成功时为 Transaction 记录的实际价格和币种 | `24.99`, `USD` |

当前代码里的促销属性表：

| 促销页 | `promotion_id` | `promotion_name` | `creative_name` | `creative_slot` | `offer_variant` / `billing_period` | Product ID |
| --- | --- | --- | --- | --- | --- | --- |
| 普通会员页（游客） | `membership_guest` | `membership` | `membership_guest` | 实际入口，如 `onboarding`、`home_membership` | `pro` 或 `proPlus` / `annual` 或 `weekly` | `pro_yearly`, `pro_weekly`, `proplus_yearly`, `proplus_weekly` |
| 普通会员页（已登录） | `membership_signed_in` | `membership` | `membership_signed_in` | 实际入口 | `pro` 或 `proPlus` / `annual` 或 `weekly` | `loged_pro_yearly`, `loged_pro_weekly`, `loged_proplus_yearly`, `loged_proplus_weekly` |
| 限时优惠弹窗 | `limited_time_offer` | `limited_time` | `limited_time_popup` | `membership_follow_up`, `follow_up_offer` 或 `returning_offer` | `limited_time` / `annual` | `limited_time_offer_yearly` |
| 老用户超级大奖 | `super_prize` | `returning_offer` | `super_prize_ticket` | `returning_offer` | `super_prize` / `weekly` | `super_prize_weekly` |
| 夏日促销（CMS） | CMS `offer.id` | `summer_sale` | `summer_discount_sign` | CMS `offer.placement` | `summer_sale_weekly` 或 `summer_sale_annual` / 对应周期 | CMS 周/年 Product ID |
| 老用户家庭优惠 | `returning_family` | `returning_offer` | `returning_family` | 实际入口 | `returning_family` / `weekly` | `family_exclusive_weekly` |
| 老用户挽留优惠 | `returning_retention` | `returning_offer` | `returning_retention` | 实际入口 | `returning_retention` / `weekly` | `family_exclusive_weekly` |
| 三日免费试用 | `three_day_trial` | `returning_offer` | `three_day_trial` | `returning_offer` 或 `membership_follow_up` | `three_day_trial` / `annual` | `3dayfreetrial_yearly` |

标准分析漏斗为：

`view_promotion` → `select_promotion` → `begin_checkout` → `subscription_result(result = purchased)`

建议按 `promotion_id + product_id` 同时拆分。`product_id` 回答“哪个 SKU 产生收益”，`promotion_id` 和 `creative_slot` 回答“哪种促销手段、哪个入口带来收益”。同一个 Product ID 被多个促销共用时，也能依靠促销上下文正确区分。

收益口径分两层：

1. Firebase IAP 收入报表以验证后的 StoreKit 2 `Analytics.logTransaction` 为准，避免再上报 `purchase` 导致收入重复。
2. 促销运营看板可筛选 `subscription_result.result = purchased`，按 `promotion_id` 汇总交易 `value` 并按 `currency` 分组；跨币种合计前需统一汇率。
3. 这里的 `value` 是顾客交易价格，不等于扣除 Apple 佣金、税费后的净收入；财务结算和净收益必须使用 App Store Connect 财务报告。

## 用户属性

| 属性 | 值 | 用途 |
| --- | --- | --- |
| `auth_state` | `signed_in` / `signed_out` | 对比登录前后转化 |
| `subscription_status` | `active` / `inactive` | 区分订阅用户行为 |

Firebase User ID 只使用后端身份令牌中的非 PII 用户 ID，不使用邮箱。

## 核心指标

1. 引导完成率：`tutorial_complete / tutorial_begin`。
2. 登录成功率：成功的 `auth_result / auth_attempt`，按 `method` 拆分。
3. 模板详情点击率：`template_detail_view / select_content`。
4. Try Now 转化率：`template_try_now / template_detail_view`。
5. 生成提交率：`generation_submitted / generation_start`。
6. 生成成功率：`generation_complete / generation_submitted`，按 `item_id`、`model_type`、`resolution` 分析。
7. 促销点击率：`select_promotion / view_promotion`，按 `promotion_id`、`creative_slot` 分析。
8. 结账调起率：`begin_checkout / select_promotion`，按 `product_id` 分析商品可用性。
9. 促销购买转化率：成功的 `subscription_result / view_promotion`，按 `promotion_id`、`offer_variant`、`product_id` 分析。
10. 促销收益：成功 `subscription_result` 的 `value` 合计，按 `promotion_id`、`creative_slot`、`product_id` 拆分，币种分别统计。

## Firebase 控制台配置

在 Analytics > Custom definitions 注册以下高频参数为自定义维度：

`source`、`result`、`failure_type`、`failure_stage`、`content_type`、`item_id`、`paywall_variant`、`product_id`、`resolution`、`method`、`promotion_id`、`promotion_name`、`creative_name`、`creative_slot`、`offer_variant`、`billing_period`。

将 `credits_cost`、`input_count`、`duration_seconds`、`elapsed_ms`、`value` 注册为自定义指标。开发验证时给 Xcode Scheme 加启动参数 `-FIRAnalyticsDebugEnabled`，在 Firebase DebugView 实时检查事件。
