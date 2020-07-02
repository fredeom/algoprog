MS_PER_YEAR = 1000 * 60 * 60 * 24 * 365.25

export getClassStartingFromJuly = (year) -> return getClass(new Date(year, 6, 1))

export getYears = (clas) ->
    now = new Date()
    return new Date(((11-(clas))+now.getFullYear() + (6 + now.getMonth())/12),0,1)

export default getClass = (graduateDate) ->
    now = new Date()
    time = graduateDate - now
    if time < 0
        return null
    else
        return 11 - Math.floor(time / MS_PER_YEAR)