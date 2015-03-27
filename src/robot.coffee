
fs = require 'fs'
ChildProcess = require 'child_process'
Github = require 'github'
winston = require 'winston'
argv = require 'optimist'
    .default 'c', 'config.json'
    .argv

logger = new winston.Logger
    transports: [
        new winston.transports.Console
            handleExceptions:   yes
            level:              'info'
            prettyPrint:        yes
            colorize:           yes
            timestamp:          yes
    ]
    exitOnError: no
    levels:
        info:   0
        warn:   1
        error:  3
    colors:
        info:   'green'
        warn:   'yellow'
        error:  'red'

if not fs.existsSync argv.c
    process.exit 1

config = JSON.parse fs.readFileSync argv.c
github = new Github version: '3.0.0'


list = []
delayedTable = {}
delay = (time, fn, id) ->
    return if delayedTable[id]?

    list.push [Date.now() + time, fn, id]
    delayedTable[id] = yes


setInterval () ->
    cb = list.shift()
    now = Date.now()

    if cb?
        [time, fn, id] = cb
        
        if now >= time
            delete delayedTable[id]
            fn()
        else
            list.push cb
, 5000


github.authenticate
    username: config.username
    password: config.password
    type: 'basic'


# 处理条目
processIssues = (issues, repo) ->
    issues.forEach (issue) ->
        logger.info "found deploy issue /#{repo.user}/#{repo.name}/issues/#{issue.number}"

        logger.info "assigning to self(#{config.username})"
        github.issues.edit
            user: repo.user
            repo: repo.name
            number: issue.number
            assignee: config.username

        # 发布函数
        deploy = (id, delayed = no) ->
            logger.info "deploying #{id}"

            self = this
            ChildProcess.exec repo.command, (err, result, error) ->
                body = ''
                close = yes

                if err
                    logger.error err

                    if delayed
                        body += "再次尝试，上线失败\n\n"
                    else
                        close = no
                        body += "上线过程遇到了错误, 请尝试修复它, 我将在五分钟后再次尝试上线一次\n\n"
                        delay 300000, (-> deploy id, yes), id
                    
                    body += "## 控制台输出\n```\n#{result}\n```\n\n" if result.length > 0
                    body += "## 错误输出\n```\n#{error}\n```\n\n" if error.length > 0
                else
                    body += "上线成功\n\n"
                    body += "## 控制台输出\n```\n#{result}\n```\n\n" if result.length > 0
            
                # 发布报告
                github.issues.createComment
                    user: repo.user
                    repo: repo.name
                    number: issue.number
                    body: body
                , (err) ->
                    if close
                        # 关闭issue
                        github.issues.edit
                            user: repo.user
                            repo: repo.name
                            number: issue.number
                            assignee: null
                            state: 'closed'

        # 及时发布状态
        logger.info "posting a comment"
        if  repo.confirm?
            users = repo.confirm.split ','

            github.issues.createComment
                user: repo.user
                repo: repo.name
                number: issue.number
                body: '正在等待 ' + ((users.map (user) -> '@' + user).join ', ') + ' 的确认'
            , (err, currentComment) ->
                delayDeploy = ->
                    self = this
                    
                    logger.info "fetching comments from issue /#{repo.user}/#{repo.name}/issues/#{issue.number}"
                    github.issues.getComments
                        user: repo.user
                        repo: repo.name
                        number: issue.number
                        per_page: 100
                    , (err, comments) ->
                        throw err if err?

                        for comment in comments
                            if comment.user.login in users and comment.id > currentComment.id
                                logger.info "got comment /#{repo.user}/#{repo.name}/issues/#{issue.number}##{comment.id}"

                                if comment.body.match /^\s*confirm/i
                                    return github.issues.createComment
                                        user: repo.user
                                        repo: repo.name
                                        number: issue.number
                                        body: "收到确认信息, 正在上线..."
                                    , (err) ->
                                        deploy "/#{repo.user}/#{repo.name}/issues/#{issue.number}#deploy"
                                else if comment.body.match /^\s*stop/i
                                    logger.info "closing issue /#{repo.user}/#{repo.name}/issues/#{issue.number}"

                                    return github.issues.createComment
                                        user: repo.user
                                        repo: repo.name
                                        number: issue.number
                                        body: "由于 @#{comment.user.login} 终止了上线流程, 本次上线被关闭"
                                    , (err) ->
                                        github.issues.edit
                                            user: repo.user
                                            repo: repo.name
                                            number: issue.number
                                            assignee: null
                                            state: 'closed'
                            
                        delay 15000, delayDeploy, "/#{repo.user}/#{repo.name}/issues/#{issue.number}"
                delay 15000, delayDeploy, "/#{repo.user}/#{repo.name}/issues/#{issue.number}"
        else
            github.issues.createComment
                user: repo.user
                repo: repo.name
                number: issue.number
                body: '正在上线...'
            , (err, currentComment) ->
                throw err if err?
                deploy "/#{repo.user}/#{repo.name}/issues/#{issue.number}#deploy"


setInterval () ->
    for repo in config.repos
        do (repo) ->
            logger.info "fetching repo #{repo.name}"
            github.issues.repoIssues
                user: repo.user
                repo: repo.name
                labels: repo.labels
                state: 'open'
                assignee: 'none'
            , (err, issues) ->
                throw err if err?
                processIssues issues, repo
, 15000

