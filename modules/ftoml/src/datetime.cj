package ftoml

import fjson.*

/*
 * TOML's four kinds of time, which `std.time` does not have - its `DateTime` is always an instant
 * in a zone. Seconds may be left out (TOML 1.1), and read as `:00`; a fraction keeps its first
 * nine digits, the rest truncated, as the spec asks. Each is written as RFC 3339 has it, and as
 * such a string in JSON.
 */

/** A day, without any relation to a zone: `1979-05-27`. */
public struct LocalDate <: Equatable<LocalDate> & ToString {
    /**
     * @throws IllegalArgumentException - if there is no such day
     */
    public LocalDate(public let year: Int64, public let month: Int64, public let day: Int64) {
        if (year < 0 || year > 9999 || month < 1 || month > 12 || day < 1 || day > daysIn(year, month)) {
            throw IllegalArgumentException("no such date: ${year}-${month}-${day}")
        }
    }

    /**
     * @throws IllegalArgumentException - if `text` is not a date
     */
    public static func parse(text: String): LocalDate {
        match (parseWhole(text)) {
            case AsLocalDate(v) => v
            case _ => throw IllegalArgumentException("not a local date: ${text}")
        }
    }

    public operator func ==(other: LocalDate): Bool {
        year == other.year && month == other.month && day == other.day
    }

    public operator func !=(other: LocalDate): Bool {
        !(this == other)
    }

    public func toString(): String {
        "${pad(year, 4)}-${pad(month, 2)}-${pad(day, 2)}"
    }
}

/** A time of day, without any relation to a day or a zone: `07:32:00.5`. */
public struct LocalTime <: Equatable<LocalTime> & ToString {
    /**
     * @throws IllegalArgumentException - if there is no such time; `second` may be 60, a leap second
     */
    public LocalTime(
        public let hour: Int64,
        public let minute: Int64,
        public let second!: Int64 = 0,
        public let nanosecond!: Int64 = 0
    ) {
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 60 || nanosecond < 0 ||
            nanosecond > 999_999_999) {
            throw IllegalArgumentException("no such time: ${hour}:${minute}:${second}.${nanosecond}")
        }
    }

    /**
     * @throws IllegalArgumentException - if `text` is not a time
     */
    public static func parse(text: String): LocalTime {
        match (parseWhole(text)) {
            case AsLocalTime(v) => v
            case _ => throw IllegalArgumentException("not a local time: ${text}")
        }
    }

    public operator func ==(other: LocalTime): Bool {
        hour == other.hour && minute == other.minute && second == other.second && nanosecond == other.nanosecond
    }

    public operator func !=(other: LocalTime): Bool {
        !(this == other)
    }

    /** Seconds always, a fraction only when there is one, in as few digits as it takes. */
    public func toString(): String {
        let whole = "${pad(hour, 2)}:${pad(minute, 2)}:${pad(second, 2)}"
        if (nanosecond == 0) {
            return whole
        }
        "${whole}.${pad(nanosecond, 9).trimEnd("0")}"
    }
}

/** A day and a time of it, without any relation to a zone: `1979-05-27T07:32:00`. */
public struct LocalDateTime <: Equatable<LocalDateTime> & ToString {
    public LocalDateTime(public let date: LocalDate, public let time: LocalTime) {}

    /**
     * @throws IllegalArgumentException - if `text` is not a local date-time
     */
    public static func parse(text: String): LocalDateTime {
        match (parseWhole(text)) {
            case AsLocalDateTime(v) => v
            case _ => throw IllegalArgumentException("not a local date-time: ${text}")
        }
    }

    public operator func ==(other: LocalDateTime): Bool {
        date == other.date && time == other.time
    }

    public operator func !=(other: LocalDateTime): Bool {
        !(this == other)
    }

    public func toString(): String {
        "${date}T${time}"
    }
}

/**
 * An instant, as a local date-time and its offset from UTC: `1979-05-27T00:32:00-07:00`. Two are
 * equal when they are written alike, not when they are the same instant; `Z` and `-00:00` are an
 * offset of zero.
 */
public struct OffsetDateTime <: Equatable<OffsetDateTime> & ToString {
    /**
     * @throws IllegalArgumentException - if the offset is not within a day
     */
    public OffsetDateTime(public let dateTime: LocalDateTime, public let offsetMinutes: Int64) {
        if (offsetMinutes <= -24 * 60 || offsetMinutes >= 24 * 60) {
            throw IllegalArgumentException("no such offset: ${offsetMinutes} minutes")
        }
    }

    /**
     * @throws IllegalArgumentException - if `text` is not an offset date-time
     */
    public static func parse(text: String): OffsetDateTime {
        match (parseWhole(text)) {
            case AsOffsetDateTime(v) => v
            case _ => throw IllegalArgumentException("not an offset date-time: ${text}")
        }
    }

    public operator func ==(other: OffsetDateTime): Bool {
        dateTime == other.dateTime && offsetMinutes == other.offsetMinutes
    }

    public operator func !=(other: OffsetDateTime): Bool {
        !(this == other)
    }

    public func toString(): String {
        if (offsetMinutes == 0) {
            return "${dateTime}Z"
        }
        let sign = if (offsetMinutes < 0) { "-" } else { "+" }
        let magnitude = if (offsetMinutes < 0) { -offsetMinutes } else { offsetMinutes }
        "${dateTime}${sign}${pad(magnitude / 60, 2)}:${pad(magnitude % 60, 2)}"
    }
}

func isLeapYear(year: Int64): Bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

func daysIn(year: Int64, month: Int64): Int64 {
    match (month) {
        case 2 => if (isLeapYear(year)) { 29 } else { 28 }
        case 4 | 6 | 9 | 11 => 30
        case _ => 31
    }
}

private func pad(value: Int64, width: Int64): String {
    let digits = value.toString()
    if (digits.size >= width) {
        digits
    } else {
        "0" * (width - digits.size) + digits
    }
}

private func parseWhole(text: String): FtData {
    let bytes = unsafe { text.rawData() }
    try {
        let (data, end) = scanDateTime(bytes, 0, bytes.size)
        if (end != bytes.size) {
            throw IllegalArgumentException("not a date or a time: ${text}")
        }
        data
    } catch (e: FtException) {
        throw IllegalArgumentException("not a date or a time: ${text}: ${e.reason}")
    }
}

func isDigit(b: Byte): Bool {
    b >= 0x30 && b <= 0x39
}

/** Whether a date starts at `at`: four digits and a `-`. */
func isDateAt(bytes: Array<Byte>, at: Int64, end: Int64): Bool {
    at + 4 < end && isDigit(bytes[at]) && isDigit(bytes[at + 1]) && isDigit(bytes[at + 2]) && isDigit(bytes[at + 3]) &&
        bytes[at + 4] == 0x2D
}

/** Whether a time starts at `at`: two digits and a `:`. */
func isTimeAt(bytes: Array<Byte>, at: Int64, end: Int64): Bool {
    at + 2 < end && isDigit(bytes[at]) && isDigit(bytes[at + 1]) && bytes[at + 2] == 0x3A
}

private func twoDigits(bytes: Array<Byte>, at: Int64, end: Int64, what: String): Int64 {
    if (at + 2 > end || !isDigit(bytes[at]) || !isDigit(bytes[at + 1])) {
        throw FtException("expected two digits of the ${what}", at)
    }
    Int64(bytes[at] - 0x30) * 10 + Int64(bytes[at + 1] - 0x30)
}

private func expectByte(bytes: Array<Byte>, at: Int64, end: Int64, b: Byte, what: String): Unit {
    if (at >= end || bytes[at] != b) {
        throw FtException("expected ${what}", at)
    }
}

/**
 * The date, the time, or both, with or without an offset, at `bytes[at..end]` - wherever
 * `isDateAt` or `isTimeAt` holds - and the index past it. What follows is the caller's to check.
 *
 * @throws FtException - if it is not a valid one
 */
func scanDateTime(bytes: Array<Byte>, at: Int64, end: Int64): (FtData, Int64) {
    if (!isDateAt(bytes, at, end)) {
        let (time, past) = scanTime(bytes, at, end)
        return (AsLocalTime(time), past)
    }
    let (date, afterDate) = scanDate(bytes, at, end)
    let separated = afterDate < end &&
        (bytes[afterDate] == 0x54 || bytes[afterDate] == 0x74 ||
        (bytes[afterDate] == 0x20 && isTimeAt(bytes, afterDate + 1, end)))
    if (!separated) {
        return (AsLocalDate(date), afterDate)
    }
    let (time, afterTime) = scanTime(bytes, afterDate + 1, end)
    let dateTime = LocalDateTime(date, time)
    if (afterTime >= end) {
        return (AsLocalDateTime(dateTime), afterTime)
    }
    match (bytes[afterTime]) {
        case 0x5A | 0x7A => (AsOffsetDateTime(OffsetDateTime(dateTime, 0)), afterTime + 1)
        case 0x2B | 0x2D =>
            let hours = twoDigits(bytes, afterTime + 1, end, "offset's hour")
            expectByte(bytes, afterTime + 3, end, 0x3A, "`:` in the offset")
            let minutes = twoDigits(bytes, afterTime + 4, end, "offset's minute")
            if (hours > 23 || minutes > 59) {
                throw FtException("no such offset", afterTime)
            }
            let offset = if (bytes[afterTime] == 0x2D) { -(hours * 60 + minutes) } else { hours * 60 + minutes }
            (AsOffsetDateTime(OffsetDateTime(dateTime, offset)), afterTime + 6)
        case _ => (AsLocalDateTime(dateTime), afterTime)
    }
}

private func scanDate(bytes: Array<Byte>, at: Int64, end: Int64): (LocalDate, Int64) {
    let year = twoDigits(bytes, at, end, "year") * 100 + twoDigits(bytes, at + 2, end, "year")
    expectByte(bytes, at + 4, end, 0x2D, "`-` in the date")
    let month = twoDigits(bytes, at + 5, end, "month")
    expectByte(bytes, at + 7, end, 0x2D, "`-` in the date")
    let day = twoDigits(bytes, at + 8, end, "day")
    if (month < 1 || month > 12 || day < 1 || day > daysIn(year, month)) {
        throw FtException("no such date", at)
    }
    (LocalDate(year, month, day), at + 10)
}

private func scanTime(bytes: Array<Byte>, at: Int64, end: Int64): (LocalTime, Int64) {
    let hour = twoDigits(bytes, at, end, "hour")
    expectByte(bytes, at + 2, end, 0x3A, "`:` in the time")
    let minute = twoDigits(bytes, at + 3, end, "minute")
    var i = at + 5
    var second = 0
    var nanosecond = 0
    if (i < end && bytes[i] == 0x3A) {
        second = twoDigits(bytes, i + 1, end, "second")
        i += 3
        if (i < end && bytes[i] == 0x2E) {
            i++
            let fraction = i
            var scale = 100_000_000
            while (i < end && isDigit(bytes[i])) {
                nanosecond += Int64(bytes[i] - 0x30) * scale
                scale /= 10
                i++
            }
            if (i == fraction) {
                throw FtException("expected a digit of the fraction", i)
            }
        }
    }
    if (hour > 23 || minute > 59 || second > 60) {
        throw FtException("no such time", at)
    }
    (LocalTime(hour, minute, second: second, nanosecond: nanosecond), i)
}

extend LocalDate <: ToJson & FromJson<LocalDate> {
    public func toJson(w: FjWriter): Unit {
        w.string(toString())
    }

    public static func fromJson(r: FjReader): LocalDate {
        fromJsonString(r) {text => LocalDate.parse(text)}
    }
}

extend LocalTime <: ToJson & FromJson<LocalTime> {
    public func toJson(w: FjWriter): Unit {
        w.string(toString())
    }

    public static func fromJson(r: FjReader): LocalTime {
        fromJsonString(r) {text => LocalTime.parse(text)}
    }
}

extend LocalDateTime <: ToJson & FromJson<LocalDateTime> {
    public func toJson(w: FjWriter): Unit {
        w.string(toString())
    }

    public static func fromJson(r: FjReader): LocalDateTime {
        fromJsonString(r) {text => LocalDateTime.parse(text)}
    }
}

extend OffsetDateTime <: ToJson & FromJson<OffsetDateTime> {
    public func toJson(w: FjWriter): Unit {
        w.string(toString())
    }

    public static func fromJson(r: FjReader): OffsetDateTime {
        fromJsonString(r) {text => OffsetDateTime.parse(text)}
    }
}

private func fromJsonString<T>(r: FjReader, parse: (String) -> T): T {
    let at = r.position
    let text = r.readString()
    try {
        parse(text)
    } catch (e: IllegalArgumentException) {
        throw FjException("${e.message} at byte ${at}")
    }
}
