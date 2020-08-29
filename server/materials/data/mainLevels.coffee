import label from "../lib/label"
import level from "../lib/level"

import arithmeticalOperations from './topics/arithmeticalOperations'
import ifs from './topics/ifs'
import debugging from './topics/debugging'
import loops from './topics/loops'
import arrays from './topics/arrays'
import strings from './topics/strings'
import floats from './topics/floats'

TOPICS_PER_LEVEL = 3

ALL_TOPICS = [
    arithmeticalOperations,
    ifs,
    debugging,
    loops,
    arrays,
    strings,
    floats
]

class TopicGenerator
    constructor: () ->
        @lastTopicId = -1

    nextTopic: () ->
        @lastTopicId++
        if @lastTopicId >= ALL_TOPICS.length
            return null
        return ALL_TOPICS[@lastTopicId]


minorLevel = (generator, id) ->
    topics = []
    topicsCount = 0
    while true
        if topicsCount == TOPICS_PER_LEVEL
            break
        nextTopic = generator.nextTopic()
        if not nextTopic
            break
        nextTopic = nextTopic()
        if not nextTopic.topic
            nextTopic = {topic: nextTopic}
        {topic, count=true} = nextTopic
        topics.push topic
        if count
            topicsCount++
    if topics.length == 0
        console.log "Return null minorLevel"
        return null
    return level(id, [
                label("<p>Чтобы перейти на следующий уровень, надо решить все задачи.</p>"),
                topics...
            ])

majorLevel = (generator, id) ->
    subLevels = [
        minorLevel(generator, "#{id}А"),
        minorLevel(generator, "#{id}Б")
    ]
    subLevels = (l for l in subLevels when l)
    if subLevels.length == 0
        console.log "Return null majorLevel"
        return null
    return level("#{id}", [
        subLevels...
    ])

export default mainLevels = () ->
    allLevels = []
    id = 1
    generator = new TopicGenerator()
    while true
        nextLevel = majorLevel(generator, id)
        if not nextLevel
            break
        allLevels.push nextLevel
        id++
    return allLevels
