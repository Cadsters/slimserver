
-- Use DELETE instead of TRUNCATE, as TRUNCATE seems to need unlocked tables.
DELETE FROM tracks;

DELETE FROM playlist_track;

DELETE FROM albums;

DELETE FROM years;

DELETE FROM contributors;

DELETE FROM contributor_track;

DELETE FROM contributor_album;

DELETE FROM genres;

DELETE FROM genre_track;

DELETE FROM comments;

DELETE FROM pluginversion;

DELETE FROM unreadable_tracks;

DELETE FROM scanned_files;

DELETE FROM works;

DELETE FROM library_track;
DELETE FROM library_album;
DELETE FROM library_contributor;
DELETE FROM library_genre;

-- these table are created by the Fulltext Search plugin
DROP TABLE IF EXISTS fulltext;
DROP TABLE IF EXISTS fulltext_terms;

UPDATE metainformation SET value = 0 WHERE name = 'lastRescanTime';
