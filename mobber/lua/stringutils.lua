--[[
String Functions

functions in this module

fixsql - usage: fixsql(sql, likeOperator)
	change quotes to double single quotes

stripColors - usage: stripColors(str)
	remove color codes from string
	
toPascalCase - usage toPascalCase(str)
	captialize the beginning of each word
	
formatSeconds - usage formatSeconds(seconds)
	convert seconds to hrs mins secs
--]]


function fixsql(sql, likeOperator)
	if (sql) then
		if (likeOperator) then
			if (likeOperator == "left") then
				sql = "'%" .. string.gsub(sql, "'", "''") .. "'";
			elseif (likeOperator == "right") then
				sql = "'" .. string.gsub(sql, "'", "''") .. "%'";
			else
				sql = "'%" .. string.gsub(sql, "'", "''") .. "%'";
			end
		else
			sql = "'" .. string.gsub(sql, "'", "''") .. "'";
		end
	else
		sql = "NULL;"
	end

	return sql;
end

function stripColors(str)
   str = str:gsub("@@", "\0");  -- change @@ to 0x00
   str = str:gsub("@%-", "~");    -- fix tildes (historical)
   str = str:gsub("@x%d?%d?%d?", ""); -- strip valid and invalid xterm color codes
   str = str:gsub("@.([^@]*)", "%1"); -- strip normal color codes and hidden garbage
   return (str:gsub("%z", "@")); -- put @ back (has parentheses on purpose)
end

function toPascalCase(str)
	str = string.gsub(str, "(%a)([%w_']*)", 
		function (first, rest)
			return first:upper()..rest:lower();
		end
	);
	return str;
end

function wrap(line, length)
  local lines = {};
  
  length = length or 10;
  
  while (#line > length) do
    -- find a space not followed by a space, or a , closest to the end of the line
    local col = string.find(line:sub(1, length), "[%s,][^%s,]*$");
	
    if (col and col > 2) then
		-- col = col - 1  -- use the space to indent
    else
      col = length  -- just cut off at wrap_column
    end -- if

    table.insert(lines, line:sub(1, col));
    line = line:sub(col + 1);
  end
  
  table.insert(lines, line);
  
  return lines;
end

function formatSeconds(seconds)
	if (not tonumber(seconds)) then
		return seconds;
	end
	
	if (seconds < 1) then
		return string.format("%.2fs", seconds);
	end
	
	local hours = math.floor(seconds / 3600);
	
	seconds = seconds % 3600
	
	local mins = math.floor(seconds / 60);
	
	seconds = math.floor(seconds % 60);
	
	local duration = "";
	
	if (hours > 0) then
		duration = hours .. "h ";
	end
	
	if (mins > 0) then
		duration = duration .. mins .. "m ";
	end
	
	if (seconds > 0) then
		duration = duration .. seconds .. "s";
	end
	
	return duration;
end