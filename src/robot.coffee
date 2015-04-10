
fs = require 'fs'
ChildProcess = require 'child_process'
Github = require 'github'
winston = require 'winston'
adapters = ['github']
argv = require 'optimist'
    .default 'c', 'config.json'
    .default 't', 'github'
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
    throw new Error 'Missing config file'

if argv.t not in adapters
    throw new Error "Adapter #{argv.t} is not exists"

config = JSON.parse fs.readFileSync argv.c
adapter = new (require './adapter/' + argv.t) config


list = []
delayed = {}
delay = (time, fn, id) ->
    return if delayed[id]?

    list.push [Date.now() + time, fn, id]
    delayed[id] = yes


setInterval () ->
    cb = list.shift()
    now = Date.now()

    if cb?
        [time, fn, id] = cb
        
        if now >= time
            delete delayed[id]
            fn()
        else
            list.push cb
, 5000


setInterval ->
    logger.info 'fetching issues ...'
    adapter.scheduler process
, 15000


# 处理条目
process = (issues, repo) ->
    issues.forEach (issue) ->
        adapter.selfAssign repo, issue
        id = adapter.makeId repo, issue

        logger.info "found #{id}"

        # 发布函数
        deploy = (id, delayed = no) ->
            logger.info "deploying #{id}"

            ChildProcess.exec repo.command, (err, result, error) ->
                body = ''
                close = yes

                if err
                    logger.error err

                    if delayed
                        body += "Retry failed\n\n"
                    else
                        close = no
                        body += "An exception occurred, I'll try it again later\n\n"
                        delay 300000, (-> deploy id, yes), id
                    
                    body += "## Console\n```\n#{result}\n```\n\n" if result.length > 0
                    body += "## Error\n```\n#{error}\n```\n\n" if error.length > 0
                else
                    body += "Success\n\n"
                    body += "## Console\n```\n#{result}\n```\n\n" if result.length > 0
            
                # 发布报告
                adapter.finish repo, issue, body, close


        # 及时发布状态
        logger.info "posting comment"

        if  repo.confirm?
            users = if repo.confirm instanceof Array then repo.confirm else repo.confirm.split ','

            adapter.comment repo, issue, 'Waiting for confirmation by ' + ((users.map (user) -> '@' + user).join ', ') "\n\n> Please type `confirm` to confirm or type `stop` to cancel.", (currentComment) ->
                delayDeploy = ->
                    adapter.confirm repo, issue, users, currentComment, (repo, issue) ->
                        adapter.comment repo, issue, "Confirmation received, deploying ...", ->
                            deploy "#{id}#deploy"
                    , (repo, issue, user) ->
                        adapter.finish repo, issue, "Deployment cancelled by @#{user}", yes
                    , (repo, issue) ->
                        delay 15000, delayDeploy, id
                
                delay 15000, delayDeploy, id
        else
            adapter.comment repo, issue, 'Deploying ...', ->
                deploy "#{id}#deploy"
                            

