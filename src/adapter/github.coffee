
GithubApi = require 'github'

class Github

    # 初始化
    constructor: (@config) ->
        @github = new GithubApi version: '3.0.0'
        @github.authenticate
            username: @config.username
            password: @config.password
            type: 'basic'


    # 调度程序
    scheduler: (cb) ->
        for repo in @config.repos
            do (repo) =>
                # 获取所有相应状态的条目
                @github.issues.repoIssues
                    user: repo.user
                    repo: repo.name
                    labels: repo.labels
                    state: 'open'
                    assignee: 'none'
                , (err, issues) ->
                    throw err if err?
                    cb issues, repo


    # 生成id
    makeId: (repo, issue) ->
        "/#{repo.user}/#{repo.name}/issues/#{issue.number}"


    # 把任务标记给自己
    selfAssign: (repo, issue) ->
        @github.issues.edit
            user: repo.user
            repo: repo.name
            number: issue.number
            assignee: @config.username


    # 提交上线报告
    finish: (repo, issue, content, close) ->
        # 发布报告
        @comment repo, issue, content, =>
            if close
                # 关闭issue
                @github.issues.edit
                    user: repo.user
                    repo: repo.name
                    number: issue.number
                    assignee: null
                    state: 'closed'


    # 发布评论
    comment: (repo, issue, content, cb) ->
        @github.issues.createComment
            user: repo.user
            repo: repo.name
            number: issue.number
            body: content
        , (err, comment) ->
            throw err if err?
            cb comment


    # 等待确认
    confirm: (repo, issue, users, currentComment, confirmMatched, stopMatched, noneMatched) ->
        @github.issues.getComments
            user: repo.user
            repo: repo.name
            number: issue.number
            per_page: 100
        , (err, comments) ->
            throw err if err?

            for comment in comments
                if comment.user.login in users and comment.id > currentComment.id
                    if comment.body.match /^\s*confirm/i
                        return confirmMatched repo, issue
                    else if comment.body.match /^\s*stop/i
                        return stopMatched repo, issue, comment.user.login

            noneMatched repo, issue


module.exports = Github

