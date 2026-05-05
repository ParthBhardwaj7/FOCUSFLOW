import {
  parseDayBoundsInTimeZone,
  parseDayUtcBounds,
  isValidIanaTimeZone,
} from './ymd';

describe('ymd', () => {
  it('parseDayUtcBounds uses UTC calendar day', () => {
    const { start, end } = parseDayUtcBounds('2026-06-15');
    expect(start.toISOString()).toBe('2026-06-15T00:00:00.000Z');
    expect(end.toISOString()).toBe('2026-06-16T00:00:00.000Z');
  });

  it('parseDayBoundsInTimeZone aligns local midnight to UTC for fixed offset zone', () => {
    const { start, end } = parseDayBoundsInTimeZone('2026-06-15', 'UTC');
    expect(start.toISOString()).toBe('2026-06-15T00:00:00.000Z');
    expect(end.toISOString()).toBe('2026-06-16T00:00:00.000Z');
  });

  it('parseDayBoundsInTimeZone uses wall calendar in Tokyo', () => {
    const { start, end } = parseDayBoundsInTimeZone('2026-06-15', 'Asia/Tokyo');
    expect(start.toISOString()).toBe('2026-06-14T15:00:00.000Z');
    expect(end.toISOString()).toBe('2026-06-15T15:00:00.000Z');
  });

  it('isValidIanaTimeZone rejects empty and accepts known zones', () => {
    expect(isValidIanaTimeZone('')).toBe(false);
    expect(isValidIanaTimeZone('  ')).toBe(false);
    expect(isValidIanaTimeZone('Not/AZone')).toBe(false);
    expect(isValidIanaTimeZone('America/Los_Angeles')).toBe(true);
  });
});
