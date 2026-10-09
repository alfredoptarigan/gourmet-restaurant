-- The day the player last answered the daily quiz, by the server's calendar.
alter table profiles add column quiz_answered_on date;
