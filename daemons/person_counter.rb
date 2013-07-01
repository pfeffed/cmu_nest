#!/usr/bin/ruby

require 'rubygems'
require 'mysql2'
require 'json'

##### Configuration Options #####
$short_motion_interval = 1

##### Get database credentials #####
begin
	json = File.read('../password_conf.json')
	password_json = JSON.parse(json)
	$db_user = password_json["db_user"]
	$db_pass = password_json["db_pass"]
	$db_path = password_json["db_path"]
	$db_name = password_json["db_name"]
rescue Exception => e
	puts "Error: Password configuration file not found or not valid."
    exit
end

##### Helper Method Declarations #####
def initializeDatabase
	begin
		client = Mysql2::Client.new(:host => $db_path, :database => $db_name, :username => $db_user, :password => $db_pass)
	rescue Exception => e
		puts "Error: Could not connect to database."
	    exit
	end
end

def getRecordsInInterval(threshold_time, min, max)
	# Get results in interval
	results = $sql_client.query("SELECT timestamp, mac AS sensor, motion, acc_z, light FROM readings WHERE timestamp > #{threshold_time} AND mac >= #{min} AND mac <= #{max}")
	# Get all unique macs in interval
	unique_sensors = []
	results.each do |record|
		unique_sensors.push(record['sensor'])
	end
	unique_sensors = unique_sensors.uniq.sort
	return unique_sensors, results
end

def analyzeMotionReadings(unique_sensors, results)
	# instantiate an empty associative array
	analysis = {}
	unique_sensors.each do |sensor|
		analysis[sensor] = {}
		analysis[sensor]['reading_count'] = 0
		analysis[sensor]['hit_count'] = 0
		analysis[sensor]['hit_rate'] = 0
	end

	# count number of hits and total readings for each sensor
	results.each do |record|
		analysis[record['sensor']]['reading_count'] += 1
		analysis[record['sensor']]['hit_count'] += record['motion']>950 ? 1 : 0
	end

	analysis.each do |k,v|
		v['hit_rate'] = v['hit_count'].to_f / v['reading_count']
	end

	return analysis
end

def count_minimum_occupancy_cmil_front(count_array)
	debug = false
	print "#{count_array} \t" if debug
	people_count = 0
	if  count_array[0] == 1 && count_array[2] == 1 && count_array[3] == 1   # Overlap of 1,3,4
		count_array[0] =       count_array[2] =       count_array[3] = 0
		people_count += 1
	end
	if  count_array[1] == 1 && count_array[2] == 1 && count_array[4] == 1   # Overlap of 2,3,5
		count_array[1] =       count_array[2] =       count_array[4] = 0
		people_count += 1
	end
	if  count_array[0] == 1 && count_array[1] == 1  # Overlap of 1,2
		count_array[0] =       count_array[1] = 0
		people_count += 1
	end
	if  count_array[0] == 1 && count_array[2] == 1  # Overlap of 1,3
		count_array[0] =       count_array[2] = 0
		people_count += 1
	end
	if  count_array[0] == 1 && count_array[3] == 1  # Overlap of 1,4
		count_array[0] =       count_array[3] = 0
		people_count += 1
	end
	if  count_array[1] == 1 && count_array[2] == 1  # Overlap of 2,3
		count_array[1] =       count_array[2] = 0
		people_count += 1
	end
	if  count_array[1] == 1 && count_array[4] == 1  # Overlap of 2,5
		count_array[1] =       count_array[4] = 0
		people_count += 1
	end
	if  count_array[2] == 1 && count_array[3] == 1  # Overlap of 3,4
		count_array[2] =       count_array[3] = 0
		people_count += 1
	end
	if  count_array[2] == 1 && count_array[4] == 1  # Overlap of 3,5
		count_array[2] =       count_array[4] = 0
		people_count += 1
	end
	if  count_array[3] == 1 && count_array[4] == 1  # Overlap of 4,5
		count_array[3] =       count_array[4] = 0
		people_count +=	 1
	end
	count_array.each{ |x| people_count += x }
	print "#{people_count}\n" if debug
	return people_count

end

##### Begin Program Execution #####
$sql_client = initializeDatabase
while(true) do
	now = Time.now.to_i

	# Find short motion interval records
	threshold_time = now - $short_motion_interval
	unique_sensors_short, short_interval_results = getRecordsInInterval(threshold_time, 10170400, 10170405)

	# Calculate minimum room occupancy
	analysis = analyzeMotionReadings(unique_sensors_short, short_interval_results)
	count_array = []
	analysis.each do |k,v|
		count_array.push(v['hit_count'] > 0 ? 1 : 0)
	end
	people_count = count_minimum_occupancy_cmil_front(count_array)

	puts "Minimum Occupancy of CMIL Front Lab: #{people_count}\nHere's how I know: #{count_array}" unless count_array.size < 5

	sleep $short_motion_interval 
end