
自动部署机器人
=============

将你从繁冗的部署工作中解放出来，让你的部署流程更加自动化

特点
----

- 与Github深度整合，利用Github API读取相关部署指令，并及时反馈部署情况
- 与人工部署不同的是，自动部署不会疲劳，也不会喊累，你永远可以不停地折腾它

使用方法
--------

执行以下命令安装

```
npm install -g deploy-robot
```

使用以下命令启动脚本

```
deploy-robot -c config.json
```

config.json文件
--------------

参考目录下地config.json.sample文件

```javascript
{
    "username": "",     // 用户名
    "password": "",     // token，去user/settings申请

    "repos": [          // 需要监听地repo列表
        {
            "user": "xxx",      // repo所属用户名
            "name": "xxx",      // repo名
            "labels": "xxx",    // 指定issue的label
            "command": "xxx",   // 上线脚本的命令
            "confirm": null     // 上线是否需要某人的确认, 默认为空
        }
    ]
}
```

提交上线请求
-----------

见下图

![deploy](http://joyqi.qiniudn.com/deploy.gif)

