"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getLocalDate = getLocalDate;
exports.getYesterday = getYesterday;
exports.getTomorrow = getTomorrow;
exports.daysBetween = daysBetween;
exports.isValidDateString = isValidDateString;
exports.calculateQuietHoursSpan = calculateQuietHoursSpan;
function getLocalDate(timezone, date = new Date()) {
    const formatter = new Intl.DateTimeFormat('en-CA', {
        timeZone: timezone,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
    });
    return formatter.format(date);
}
function getYesterday(dateStr) {
    const [year, month, day] = dateStr.split('-').map(Number);
    const date = new Date(year, month - 1, day);
    date.setDate(date.getDate() - 1);
    return date.toISOString().split('T')[0];
}
function getTomorrow(dateStr) {
    const [year, month, day] = dateStr.split('-').map(Number);
    const date = new Date(year, month - 1, day);
    date.setDate(date.getDate() + 1);
    return date.toISOString().split('T')[0];
}
function daysBetween(dateStr1, dateStr2) {
    const [y1, m1, d1] = dateStr1.split('-').map(Number);
    const [y2, m2, d2] = dateStr2.split('-').map(Number);
    const date1 = new Date(y1, m1 - 1, d1);
    const date2 = new Date(y2, m2 - 1, d2);
    const diffTime = Math.abs(date2.getTime() - date1.getTime());
    return Math.floor(diffTime / (1000 * 60 * 60 * 24));
}
function isValidDateString(dateStr) {
    const pattern = /^\d{4}-\d{2}-\d{2}$/;
    if (!pattern.test(dateStr))
        return false;
    const [year, month, day] = dateStr.split('-').map(Number);
    const date = new Date(year, month - 1, day);
    return (date.getFullYear() === year &&
        date.getMonth() === month - 1 &&
        date.getDate() === day);
}
function calculateQuietHoursSpan(start, end) {
    const [startHour, startMin] = start.split(':').map(Number);
    const [endHour, endMin] = end.split(':').map(Number);
    const startMinutes = startHour * 60 + startMin;
    let endMinutes = endHour * 60 + endMin;
    if (endMinutes <= startMinutes) {
        endMinutes += 24 * 60;
    }
    return (endMinutes - startMinutes) / 60;
}
//# sourceMappingURL=date.utils.js.map