----------------------------------
-- sqlite3 Helper Module
----------------------------------

sqlitedb = {
	path = GetPluginInfo(GetPluginID(), 20),
	name = "sqlite.db",
	db = nil
};

function sqlitedb:new(db)
	db = db or {};
	setmetatable(db, self);
	self.__index = self;
	return db;
end

function sqlitedb:open()
	if (self.db == nil or not self.db:isopen()) then
		self.db = assert(sqlite3.open(self.path .. self.name));
		self:pragma();
	end
end

function sqlitedb:close()
	if (self.db) then
		if (self.db:isopen()) then
			local code = self.db:close();
			self:check(code);
		end
		
		self.db = nil;
	end
end

function sqlitedb:check(code)
	if (code ~= sqlite3.OK and
		code ~= sqlite3.ROW and
		code ~= sqlite3.DONE) then

		local err = self.db:errmsg();
		self.db:execute("ROLLBACK;");
		error("REPORT THIS ERROR TO RAURU:\r\n" .. err, 2);
	end
end

function sqlitedb:exec(sql, checkCode, callback)
	assert(sqlite3.complete(sql), "Not an SQL statement: " .. sql);
	
	local code = self.db:execute(sql, callback);
	
	if (checkCode) then
		self:check(code);
	end
	
	return code;
end

function sqlitedb:pragma()
	self:exec("PRAGMA foreign_keys=ON;", true);
end

function sqlitedb:gettable(sql)
	assert(sqlite3.complete(sql), "Not an SQL statement:\r\n" .. sql);
	
	local results = {};
	
	for row in self.db:nrows(sql) do
		table.insert(results, row);
	end
	
	return results;
end

function sqlitedb:changes()
	return self.db:changes();
end

function sqlitedb:backup()
	self:open();
	
	local isDatabaseBackedUp;

	print("\r\n\r\nPERFORMING", self.name, "DATABASE BACKUP.");
	print("CHECKING INTEGRITY...");
	
	BroadcastPlugin(999, "repaint");
	
	local integrityCheck = true;
	
	self:exec("PRAGMA wal_checkpoint;", true);
	
	for row in self.db:nrows("PRAGMA integrity_check;") do
		if (row.integrity_check ~= "ok") then
			integrityCheck = false;
		end
	end
	
	self:close();
	
	if (not integrityCheck) then
		isDatabaseBackedUp = false;
		
		print("INTEGRITY CHECK FAILED. CLOSE MUSHCLIENT AND RESTORE A KNOWN GOOD DATABASE.");
		print("BACKUP ABORTED.\r\n\r\n");
	else
		print("INTEGRITY CHECK PASSED.");
		
		BroadcastPlugin (999, "repaint");

		local backupDir = self.path .. "db_backups\\";

		local makeDirCmd = "mkdir " .. addQuotes(backupDir);
		
		os.execute(makeDirCmd);

		local copyCmd = "copy /Y " .. addQuotes(self.path .. self.name) .. " " .. addQuotes(backupDir .. self.name .. "." .. "backup");

		os.execute(copyCmd);

		print("FINISHED DATABASE BACKUP.\r\n\r\n");
		
		self:open();
		
		isDatabaseBackedUp = true;
	end
	
	return isDatabaseBackedUp;
end

function sqlitedb:vacuum()
	local fileSizeBefore;
	local fileSizeAfter;

	self:open();

	local file = io.open(self.path .. self.name);

	fileSizeBefore = file and fsize(file) or nil;
	
	print("BEGIN VACUUM ON", self.name);
	
	local code = self:exec("VACUUM;");
	
	if (code ~= sqlite3.OK) then
		print("END VACUUM ON", self.name);
		local err = self.db:errmsg();
		self.db:execute("ROLLBACK;");
		file:close();
		error(err);
	else
		fileSizeAfter = file and fsize(file) or nil;
		file:close();
	
		if (fileSizeBefore and fileSizeAfter) then
			fileSizeBefore = fileSizeBefore / 1024;
			fileSizeAfter = fileSizeAfter / 1024;
			
			local fileSizeDif = fileSizeBefore - fileSizeAfter;
			
			print("DISK SPACE RECOVERED: " .. fileSizeDif .. " KB");
		end
		
		print("END VACUUM ON", self.name);
	end
end

function fsize(file)
	local current = file:seek();      -- get current position
	local size = file:seek("end");    -- get file size
	file:seek("set", current);        -- restore position
	return size;
end

function addQuotes(str)
	return "\"" .. str .. "\"";
end