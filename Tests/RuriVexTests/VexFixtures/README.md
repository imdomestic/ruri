# 真实 Vex SSE 录制

`stageb-sync.sse` 于 2026-10-18 JST 从 encore 的真实 Vex staging 录制，路径为 `GET /v2/projects/vex-it-stageb/rooms/main-fabric/events`。录制时房间处于 stopped，构建 `fabric-3cf4f9d4009a` 为 ready。文件包含服务器发出的 SSE 数据，没有认证请求头或凭据。

测试使用 EventSource 1.4.0 解析录制数据，检查项目范围、世界房间状态、构建标识和客户端文件选择。录制过程只读取事件，不创建房间或构建。测试运行只读取当前目录中的录制文件。

录制文件为 3,942 字节，SHA-256 为 `fdcb3d0928bb198268e20a9f720b43f168915fcf4783a5bae74012425e5ab52d`。
