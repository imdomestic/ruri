# 真实 Vex SSE 录制

`stageb-sync.sse` 于 2026-10-18 JST 从 encore 的真实 Vex staging 录制，路径为 `GET /v2/projects/vex-it-stageb/rooms/main-fabric/events`。录制时房间处于 stopped，构建 `fabric-3cf4f9d4009a` 为 ready。文件保留服务器发出的原始 SSE 字节，没有认证请求头或凭据。

测试使用 EventSource 1.4.0 解析原始数据，检查项目范围、世界房间状态、构建标识和客户端文件选择。录制过程只读取事件，不创建房间或构建。

录制文件为 3,943 字节，SHA-256 为 `8203bd287c2e5246bb4fc48b50b5f64a2d746ec6697f97c332f121c4e2120d82`，`cmp` 与原始录制输出完全一致。
