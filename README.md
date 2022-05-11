# 前言
基于[skynet](https://github.com/cloudwu/skynet)的简单服务器, 已实现功能有：
* 登陆
* 角色创建
* aoi
* 地图内移动
* 攻击

# 编译
git clone https://github.com/weiwenchen2022/mmorpg_on_skynet.git

cd mmorpg_on_skynet; make

# 安装redis
1. 安装并运行redis，监听于6379端口

# 运行服务器
1. 运行./start.sh脚本，启动服务器。

# 运行客户端
测试客户端是client/client.lua，通过命令“lua client/client.lua”。

client.lua接受用户名作为命令行参数 “lua client/client.lua username”。

client.lua会自动完成登陆相关的流程，然后等待用户输入。

用户输入以回车结束，输入内容将打包发送至服务器。
输入的格式为“命令 参数”，全部客户端命令参考proto/proto.lua文件中的c2s

一个常见的client命令流程是这样的：

```lua
lua client/client.lua

character_create character = {name = “hello”, race = “human”, class = “warrior”,}
character_list
character_pick id = 4
map_ready
move pos = {x = 123, y = 123,}
combat target = 7
```
