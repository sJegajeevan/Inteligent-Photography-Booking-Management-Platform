import test from 'node:test';
import assert from 'node:assert/strict';
import { bookingEndTimestamp, canCompleteBooking, completionAvailabilityMessage } from '../src/pages/Studio/bookingCompletion.js';

const booking = { status: 'Confirmed', bookingDate: '2026-12-01', endTime: '13:00:00' };
const end = Date.parse('2026-12-01T07:30:00Z');
test('Colombo end time maps to UTC regardless of browser timezone', () => {
  assert.equal(bookingEndTimestamp(booking), end);
  assert.equal(bookingEndTimestamp({ ...booking, endTime: '13:00' }), end);
});
test('completion requires strictly after the scheduled end', () => {
  for (const now of [end - 86400000, end - 3600000, end]) assert.equal(canCompleteBooking(booking, now), false);
  assert.equal(canCompleteBooking(booking, end + 1), true);
});
test('all other statuses remain ineligible after the end', () => {
  for (const status of ['Pending', 'Cancelled', 'Rejected', 'Completed', 'Rescheduled', 'AwaitingApproval', 'AIRecommended']) {
    assert.equal(canCompleteBooking({ ...booking, status }, end + 1), false);
  }
});
test('missing or invalid times fail closed', () => {
  for (const endTime of [null, '', '25:00:00', '13:99:00', 'invalid']) {
    assert.equal(canCompleteBooking({ ...booking, endTime }, end + 1), false);
  }
  assert.equal(canCompleteBooking(null, end + 1), false);
});
test('fractional seconds do not permit early completion', () => {
  const fractional = { ...booking, endTime: '13:00:00.0000001' };
  assert.equal(canCompleteBooking(fractional, end), false);
  assert.equal(canCompleteBooking(fractional, end + 2), true);
});
test('availability hint identifies date and Colombo time', () => {
  const message = completionAvailabilityMessage(booking);
  assert.match(message, /Available after/);
  assert.match(message, /2026/);
  assert.match(message, /1:00\s*pm/i);
  assert.match(message, /Asia\/Colombo/);
});
