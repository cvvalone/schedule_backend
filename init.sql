CREATE TABLE AppConfig (
    id TEXT PRIMARY KEY,
    institutionName TEXT NOT NULL,
    logo TEXT NOT NULL,
    policyUrl TEXT NOT NULL
);

CREATE TABLE Departments (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT
);

CREATE TABLE Groups (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    departmentId TEXT REFERENCES Departments(id) ON DELETE CASCADE,
    yearStart INTEGER NOT NULL,
    yearFinish INTEGER NOT NULL
);

CREATE TABLE Users (
    id TEXT PRIMARY KEY,
    firstName TEXT NOT NULL,
    lastName TEXT NOT NULL,
    midName TEXT,
    email TEXT UNIQUE,
    avatar TEXT,
    phone TEXT UNIQUE,
    type TEXT CHECK (type IN ('STUDENT', 'TEACHER', 'ADMIN')),
    passwordHash TEXT,
    authProvider TEXT CHECK (authProvider IN ('google', 'password')),
    groupId TEXT REFERENCES Groups(id) ON DELETE SET NULL
);

CREATE TABLE Subjects (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    shortTitle TEXT NOT NULL,
    description TEXT
);

CREATE TABLE StudentGroup (
    id TEXT PRIMARY KEY,
    groupId TEXT REFERENCES Groups(id) ON DELETE CASCADE,
    userId TEXT REFERENCES Users(id) ON DELETE CASCADE
);

CREATE TABLE CallSchedule (
    id TEXT PRIMARY KEY,
    dayNumber INTEGER CHECK (dayNumber BETWEEN 1 AND 7),
    position INTEGER NOT NULL,
    timeStart TIME NOT NULL,
    timeFinish TIME NOT NULL
);

CREATE TABLE ScheduleDay (
    id TEXT PRIMARY KEY,
    dayNumber INTEGER CHECK (dayNumber BETWEEN 1 AND 7),
    weekNumber INTEGER CHECK (weekNumber BETWEEN 1 AND 2)
);

CREATE TABLE ScheduleItem (
    id TEXT PRIMARY KEY,
    userId TEXT REFERENCES Users(id) ON DELETE SET NULL,
    subjectId TEXT REFERENCES Subjects(id) ON DELETE CASCADE,
    callScheduleId TEXT REFERENCES CallSchedule(id) ON DELETE CASCADE,
    scheduleDayId TEXT REFERENCES ScheduleDay(id) ON DELETE CASCADE,
    groupId TEXT REFERENCES Groups(id) ON DELETE CASCADE,
    room TEXT
);

CREATE TABLE Notifications (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    group_id TEXT REFERENCES Groups(id) ON DELETE CASCADE,
    user_id TEXT REFERENCES Users(id) ON DELETE SET NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO ScheduleDay (id, dayNumber, weekNumber) VALUES
('1', 1, 1),('2', 2, 1),('3', 3, 1),('4', 4, 1),('5', 5, 1),
('6', 6, 1),('7', 7, 1),('8', 1, 2),('9', 2, 2),('10', 3, 2),
('11', 4, 2),('12', 5, 2),('13', 6, 2),('14', 7, 2);
