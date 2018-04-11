connectEnsureLogin = require('connect-ensure-login')
passport = require('passport')
iconv = require('iconv-lite')
Entities = require('html-entities').XmlEntities

import User from '../models/user'
import Submit from '../models/submit'
import Result from '../models/result'
import Problem from '../models/problem'
import Table from '../models/table'
import SubmitComment from '../models/SubmitComment'
import RegisteredUser from '../models/registeredUser'
import Material from '../models/Material'
import BlogPost from '../models/BlogPost'

import dashboard from './dashboard'
import table, * as tableApi from './table'
import register from './register'
import setOutcome from './setOutcome'

import logger from '../log'

import downloadMaterials from '../cron/downloadMaterials'
import * as downloadContests from '../cron/downloadContests'
import * as downloadSubmits from "../cron/downloadSubmits"
import * as groups from '../informatics/informaticsGroups'

import InformaticsUser from '../informatics/InformaticsUser'

import {getStats} from '../lib/download'

ensureLoggedIn = connectEnsureLogin.ensureLoggedIn("/api/forbidden")
entities = new Entities()

wrap = (fn) ->
    (args...) ->
        try
            await fn(args...)
        catch error
            args[2](error)

expandSubmit = (submit) ->
    submit.fullUser = await User.findById(submit.user)
    submit.fullProblem = await Problem.findById(submit.problem)
    tableNamePromises = []
    for t in submit.fullProblem.tables
        tableNamePromises.push(Table.findById(t))
    tableNames = (await Promise.all(tableNamePromises)).map((table) -> table.name)
    submit.fullProblem.tables = tableNames
    return submit

createDraftSubmit = (problemId, userId, language, code) ->
    code = iconv.decode(new Buffer(code), "latin1")
    code = entities.encode(code)
    time = new Date
    timeStr = +time
    submit = new Submit
        _id: "#{userId}r#{timeStr}#{problemId}" ,
        time: time,
        user: userId,
        problem: problemId,
        outcome: "DR"
        source: code
        language: language
        comments: []
        results: []
        force: false
    await submit.upsert()

export default setupApi = (app) ->
    app.get '/api/forbidden', wrap (req, res) ->
        res.status(403).send('No permissions')

    app.post '/api/register', wrap register
    app.post '/api/login', passport.authenticate('local'), wrap (req, res) ->
        res.json({logged: true})

    app.get '/api/logout', wrap (req, res) ->
        req.logout()
        res.json({loggedOut: true})

    app.post '/api/submit/:problemId', ensureLoggedIn, wrap (req, res) ->
        fullProblemId = "p" + req.params.problemId
        try
            oldSubmits = await Submit.findByUserAndProblem(req.user.informaticsId, fullProblemId)
            try
                informaticsUser = await InformaticsUser.getUser(req.user.informaticsUsername, req.user.informaticsPassword)
                informaticsData = await informaticsUser.submit(req.params.problemId, req.get('Content-Type'), req.body)
            finally
                await downloadSubmits.runForUser(req.user.informaticsId, 5, 1)
        catch e
            newSubmits = await Submit.findByUserAndProblem(req.user.informaticsId, fullProblemId)
            if oldSubmits.length == newSubmits.length
                throw e
        res.json({submit: true})

    app.post '/api/submit/:problemId/draft', ensureLoggedIn, wrap (req, res) ->
        await createDraftSubmit("p" + req.params.problemId, req.user.informaticsId, req.body.language, req.body.code)
        res.json({submit: true})

    app.get '/api/me', ensureLoggedIn, wrap (req, res) ->
        user = JSON.parse(JSON.stringify(req.user))
        delete user.informaticsPassword
        res.json user

    app.get '/api/myUser', ensureLoggedIn, wrap (req, res) ->
        User.findOne({_id: req.user.informaticsId}, (err, record) ->
            res.json(record)
        )

    app.post '/api/user/:id/set', ensureLoggedIn, wrap (req, res) ->
        if not req.user?.admin
            res.status(403).send('No permissions')
            return
        cfLogin = req.body.cf.login
        if cfLogin == ""
            cfLogin = undefined
        User.findOne({_id: req.params.id}, (err, record) ->
            await record.setBaseLevel req.body.level.base
            await record.setCfLogin cfLogin
            res.send('OK')
        )

    app.get '/api/user/:id', wrap (req, res) ->
        User.findOne({_id: req.params.id}, (err, record) ->
            res.json(record)
        )

    app.get '/api/dashboard', wrap (req, res) ->
        res.json(await dashboard())

    app.get '/api/table/:userList/:table', wrap (req, res) ->
        res.json(await table(req.params.userList, req.params.table))

    app.get '/api/fullUser/:id', wrap (req, res) ->
        res.json(await tableApi.fullUser(req.params.id))

    app.get '/api/users/:userList', wrap (req, res) ->
        res.json(await User.findByList(req.params.userList))

    app.get '/api/registeredUsers', ensureLoggedIn, wrap (req, res) ->
        if not req.user?.admin
            res.status(403).send('No permissions')
            return
        res.json(await RegisteredUser.find({}))

    app.get '/api/submits/:user/:problem', ensureLoggedIn, wrap (req, res) ->
        if not req.user?.admin and ""+req.user?.informaticsId != ""+req.params.user
            res.status(403).send('No permissions')
            return
        submits = await Submit.findByUserAndProblem(req.params.user, req.params.problem)
        submits = submits.map((submit) -> submit.toObject())
        submits = submits.map(expandSubmit)
        submits = await Promise.all(submits)
        res.json(submits)

    app.get '/api/material/:id', wrap (req, res) ->
        res.json(await Material.findById(req.params.id))

    app.get '/api/lastBlogPosts', wrap (req, res) ->
        res.json(await BlogPost.findLast(5, 1000 * 60 * 60 * 24 * 60))

    app.get '/api/result/:id', wrap (req, res) ->
        result = (await Result.findById(req.params.id)).toObject()
        result.fullUser = await User.findById(result.user)
        result.fullTable = await Problem.findById(result.table)
        res.json(result)

    app.get '/api/userResults/:userId', wrap (req, res) ->
        results = (await Result.findByUser(req.params.userId))
        json = {}
        for r in results
            r = r.toObject()
            json[r._id] = r
        res.json(json)

    app.get '/api/submit/:id', ensureLoggedIn, wrap (req, res) ->
        if not req.user?.admin and ""+req.user?.informaticsId != ""+req.params.user
            res.status(403).send('No permissions')
            return
        submit = (await Submit.findById(req.params.id)).toObject()
        submit = expandSubmit(submit)
        res.json(submit)

    app.get '/api/lastComments', ensureLoggedIn, wrap (req, res) ->
        if not req.user?.informaticsId
            res.status(403).send('No permissions')
            return
        res.json(await SubmitComment.findLastNotViewedByUser(req.user?.informaticsId))

    app.get '/api/lastCommentsByProblem/:problem', ensureLoggedIn, wrap (req, res) ->
        if not req.user?.admin
            res.status(403).send('No permissions')
            return
        res.json(await SubmitComment.findLastByProblem(req.params.problem))

    app.get '/api/bestSubmits/:problem', ensureLoggedIn, wrap (req, res) ->
        allowed = false
        if req.user?.admin
            allowed = true
        else if req.user?.informaticsId
            result = await Result.findByUserAndTable(req.user?.informaticsId, req.params.problem)
            allowed = result && result.solved > 0
        if not allowed
            res.status(403).send('No permissions')
            return
        res.json(await Submit.findBestByProblem(req.params.problem, 5))

    app.post '/api/setOutcome/:submitId', ensureLoggedIn, wrap (req, res) ->
        if not req.user?.admin
            res.status(403).send('No permissions')
            return
        setOutcome(req, res)

    app.post '/api/setQuality/:submitId/:quality', ensureLoggedIn, wrap (req, res) ->
        if not req.user?.admin
            res.status(403).send('No permissions')
            return
        submit = await Submit.findById(req.params.submitId)
        if not submit
            res.status(404).send('Submit not found')
            return
        submit.quality = req.params.quality
        await submit.save()
        res.send('OK')

    app.post '/api/setCommentViewed/:commentId', ensureLoggedIn, wrap (req, res) ->
        comment = await SubmitComment.findById(req.params.commentId)
        console.log "Set comment viewed ", req.params.commentId, ""+req.user?.informaticsId, "" + comment?.userId
        if ""+req.user?.informaticsId != "" + comment?.userId
            res.status(403).send('No permissions')
            return
        comment.viewed = true
        await comment.save()
        res.send('OK')

    app.post '/api/moveUserToGroup/:userId/:groupName', ensureLoggedIn, wrap (req, res) ->
        if not req.user?.admin
            res.status(403).send('No permissions')
            return
        user = await User.findById(req.params.userId)
        if not user
            res.status(400).send("User not found")
            return
        adminUser = await InformaticsUser.findAdmin()
        await groups.moveUserToGroup(adminUser, req.params.userId, req.params.groupName)
        if req.params.groupName != "none"
            await user.setUserList(req.params.groupName)
        res.send('OK')

    app.get '/api/updateResults/:user', ensureLoggedIn, wrap (req, res) ->
        if not req.user?.admin
            res.status(403).send('No permissions')
            return
        await User.updateUser(req.params.user)
        res.send('OK')

    app.get '/api/updateAllResults', ensureLoggedIn, wrap (req, res) ->
        if not req.user?.admin
            res.status(403).send('No permissions')
            return
        User.updateAllUsers()
        res.send('OK')

    app.get '/api/updateAllCf', ensureLoggedIn, wrap (req, res) ->
        if not req.user?.admin
            res.status(403).send('No permissions')
            return
        User.updateAllCf()
        res.send('OK')

    app.get '/api/downloadMaterials', ensureLoggedIn, wrap (req, res) ->
        if not req.user?.admin
            res.status(403).send('No permissions')
            return
        downloadMaterials()
        res.send('OK')

    app.get '/api/downloadContests', ensureLoggedIn, wrap (req, res) ->
        if not req.user?.admin
            res.status(403).send('No permissions')
            return
        downloadContests.run()
        res.send('OK')

    app.get '/api/downloadSubmits/:user', ensureLoggedIn, wrap (req, res) ->
        if not req.user?.admin
            res.status(403).send('No permissions')
            return
        await downloadSubmits.runForUser(req.params.user, 100, 1e9)
        res.send('OK')

    app.get '/api/downloadAllSubmits', ensureLoggedIn, wrap (req, res) ->
        if not req.user?.admin
            res.status(403).send('No permissions')
            return
        downloadSubmits.runAll()
        res.send('OK')

    app.post '/api/informatics/userData', wrap (req, res) ->
        username = req.body.username
        password = req.body.password
        user = await InformaticsUser.getUser(username, password)
        result = await user.getData()
        res.json(result)

    app.get '/api/downloadingStats', ensureLoggedIn, wrap (req, res) ->
        if not req.user?.admin
            res.status(403).send('No permissions')
            return
        res.json(getStats())
