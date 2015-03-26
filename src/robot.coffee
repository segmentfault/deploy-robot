
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

github.authenticate
    username: config.username
    password: config.password
    type: 'basic'


# 处理条目
processIssues = (issues, repo) ->
    for issue in issues
        logger.info "found deploy issue #{repo.user}/#{repo.name}/issues/#{issue.number}"

        logger.info "assigning to self(#{config.username})"
        github.issues.edit
            user: repo.user
            repo: repo.name
            number: issue.number
            assignee: config.username

        logger.info "posting a comment"
        github.issues.createComment
            user: repo.user
            repo: repo.name
            number: issue.number
            body: '收到, 正在准备上线...'

        ChildProcess.exec repo.command, (err, result, error) ->
            body = ''
            if err
                body += "上线过程遇到了错误, 请尝试修复它, 我将在五分钟后再次尝试上线一次\n\n"
                body += "## 控制台输出\n```\n#{result}\n```\n\n" if result.length > 0
                body += "## 错误输出\n```\n#{error}\n```\n\n" if error.length > 0
                logger.error err
            else
                body += "上线成功\n\n"
                body += "## 控制台输出\n```\n#{result}\n```\n\n" if result.length > 0
                
                # 关闭issue
                github.issues.edit
                    user: repo.user
                    repo: repo.name
                    number: issue.number
                    state: 'closed'
            
            # 发布报告
            github.issues.createComment
                user: repo.user
                repo: repo.name
                number: issue.number
                body: body


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
                processIssues issues, repo
, 15000

