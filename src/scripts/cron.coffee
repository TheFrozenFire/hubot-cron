# Description:
#   register cron jobs to schedule messages on the current channel
#
# Commands:
#   hubot new job "<crontab format>" <message>   - Schedule a cron job to say something
#   hubot new job <crontab format> "<message>"   - Ditto
#   hubot new job <cronrab format> say <message> - Ditto
#   hubot list jobs - List current cron jobs
#   hubot remove job <id> - remove job
#   hubot remove job with message <message> - remove with message
#
# Author:
#   miyagawa

cronJob = require('cron').CronJob

JOBS = {}

createNewJob = (robot, pattern, user, message) ->
  id = Math.floor(Math.random() * 1000000) while !id? || JOBS[id]
  job = registerNewJob robot, id, pattern, user, message
  robot.brain.data.cronjob[id] = job.serialize()
  id

registerNewJobFromBrain = (robot, id, pattern, user, message, timezone) ->
  # for jobs saved in v0.2.0..v0.2.2
  user = user.user if "user" of user
  registerNewJob(robot, id, pattern, user, message, timezone)

registerNewJob = (robot, id, pattern, user, message, timezone) ->
  job = new Job(id, pattern, user, message, timezone)
  job.start(robot)
  JOBS[id] = job

unregisterJob = (robot, id)->
  if JOBS[id]
    JOBS[id].stop()
    delete robot.brain.data.cronjob[id]
    delete JOBS[id]
    return yes
  no

handleNewJob = (robot, msg, pattern, message) ->
  try
    id = createNewJob robot, pattern, msg.message.user, message
    msg.send "Job #{id} created"
  catch error
    msg.send "Error caught parsing crontab pattern: #{error}. See http://crontab.org/ for the syntax"

updateJobTimezone = (robot, id, timezone) ->
  if JOBS[id]
    JOBS[id].stop()
    JOBS[id].timezone = timezone
    robot.brain.data.cronjob[id] = JOBS[id].serialize()
    JOBS[id].start()
    return yes
  no

updateJobUser = (robot, id, msg) ->
  if JOBS[id]
    JOBS[id].stop()
    clonedUser = {}
    clonedUser[k] = v for k,v of msg.message.user
    JOBS[id].user = clonedUser
    robot.brain.data.cronjob[id] = JOBS[id].serialize()
    JOBS[id].start()
    return yes
  no

module.exports = (robot) ->
  robot.brain.data.cronjob or= {}
  robot.brain.on 'loaded', =>
    for own id, job of robot.brain.data.cronjob
      registerNewJobFromBrain robot, id, job...
  robot.brain.emit 'loaded' if Object.keys(robot.brain.data.cronjob).length

  robot.respond /(?:new|add) job "(.*?)" (.*)$/i, (msg) ->
    handleNewJob robot, msg, msg.match[1], msg.match[2]

  robot.respond /(?:new|add) job (.*) "(.*?)" *$/i, (msg) ->
    handleNewJob robot, msg, msg.match[1], msg.match[2]

  robot.respond /(?:new|add) job (.*?) say (.*?) *$/i, (msg) ->
    handleNewJob robot, msg, msg.match[1], msg.match[2]

  robot.respond /(?:list|ls) jobs?/i, (msg) ->
    text = ''
    for id, job of JOBS
      room = job.user.reply_to || job.user.room
      if room == msg.message.user.reply_to or room == msg.message.user.room
        text += "#{id}: #{job.pattern} @#{room} \"#{job.message}\"\n"
    msg.send text if text.length > 0

  robot.respond /(?:rm|remove|del|delete) job ([\d,]+)/i, (msg) ->
    targetJobs = msg.match[1].split(",")
    for id in targetJobs
      if unregisterJob(robot, id)
        msg.send "Job #{id} deleted"
      else
        msg.send "Job #{id} does not exist"

  robot.respond /(?:rm|remove|del|delete) job with message (.+)/i, (msg) ->
    message = msg.match[1]
    for id, job of JOBS
      room = job.user.reply_to || job.user.room
      if (room == msg.message.user.reply_to or room == msg.message.user.room) and job.message == message and unregisterJob(robot, id)
        msg.send "Job #{id} deleted"
  
  robot.respond /(?:tz|timezone) job ([\d,]+) (.*)/i, (msg) ->
    targetJobs = msg.match[1].split(",")
    for id in targetJobs
      if (timezone = msg.match[2]) and updateJobTimezone(robot, id, timezone)
        msg.send "Job #{id} updated to use #{timezone}"
      else
        msg.send "Job #{id} does not exist"
  
  robot.respond /(?:mv|move) job ([\d,]+) here/i, (msg) ->
    targetJobs = msg.match[1].split(",")
    for id in targetJobs
      if updateJobUser(robot, id, msg)
        msg.send "Job #{id} moved"
      else
        msg.send "Job #{id} does not exist"

class Job
  constructor: (id, pattern, user, message, timezone) ->
    @id = id
    @pattern = pattern
    # cloning user because adapter may touch it later
    clonedUser = {}
    clonedUser[k] = v for k,v of user
    @user = clonedUser
    @message = message
    @timezone = timezone

  start: (robot) ->
    @cronjob = new cronJob(@pattern, =>
      @sendMessage robot
    , null, false, @timezone)
    @cronjob.start()

  stop: ->
    @cronjob.stop()

  serialize: ->
    [@pattern, @user, @message, @timezone]

  sendMessage: (robot) ->
    envelope = user: @user, room: @user.room
    robot.send envelope, @message

