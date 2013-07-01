#!/usr/bin/ruby

require 'rubygems'
require 'mysql2'
require 'json'
require 'httparty'

##### Configuration Options #####
$short_motion_interval = 1
$long_motion_interval = 600
$ac_change_interval = 90

##### Room Status Trackers #####
$room_empty = false
$lights_state = nil
$light_threshold = 20  # based on empirical observation
$current_ac_state_level = nil
$pending_ac_state_level = nil
$time_last_ac_change_detected = nil

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

# def check_if_lights_turned_on_or_off(unique_sensors, results)

# 	previous_array = {}
# 	unique_sensors.each do |sensor|
# 		previous_array[sensor] = nil
# 	end

# 	light_state_by_sensor = {}
# 	unique_sensors.each do |sensor|
# 		light_state_by_sensor[sensor] = nil
# 	end

# 	results.each do |record|

# 		sensor = record['sensor']
# 		current = record['light']
# 		previous = previous_array[sensor].nil? ? current : previous_array[sensor]

# 		delta = current - previous
# 		previous_array[sensor] = current

# 		if delta > $light_threshold
# 			light_state_by_sensor[sensor] = "1"
# 			puts "Sensor #{sensor}: Winner!"
# 		elsif delta < ($light_threshold*(-1))
# 			light_state_by_sensor[sensor] = "-1"
# 			puts "Sensor #{sensor}: Loser!"
# 		end

# 	end

# 	light_status_counter = 0
# 	unique_sensors.each do |sensor|
# 		light_state_by_sensor.each do |k,v|
# 			puts "#{k}: #{v}"
# 		end
# 		light_status_counter += light_state_by_sensor[sensor].to_i unless light_state_by_sensor[sensor].nil?
# 	end

# 	puts "Light Counter: #{light_status_counter}"
# 	if light_status_counter > 2
# 		return true;
# 	elsif light_status_counter < (-2)
# 		return false;
# 	else
# 		return $lights_state
# 	end
# end

def record_air_conditioning_decision
	decision = nil
	
	if $room_empty and ave_temp<80
		decision = "turn off"
	else
		decision = "turn on"
	end
	$sql_client.query("INSERT INTO ac_decision (timestamp, decision) VALUES (#{Time.now.to_i}, '#{decision}')")
end

def analyze_air_conditioning_readings(unique_sensors, results)
	sum_z = count = sum_of_squares_z = 0
	
	results.each do |record|
		if(record['sensor'].to_i == unique_sensors[0])
			count += 1
			sum_z += record['acc_z']
		end
	end
	average_z = sum_z.to_f / count

	results.each do |record|
		if(record['sensor'] == unique_sensors[0])
			z_delta = record['acc_z'] - average_z
			sum_of_squares_z += z_delta * z_delta
		end
	end
	sum_of_squares_z = sum_of_squares_z.round(1)
	average_z = average_z.round(1)

	variance = (sum_of_squares_z.to_f/count).round

	
	if variance < 55
		$pending_ac_state_level = "off"
		$time_last_ac_change_detected = Time.now if $time_last_ac_change_detected.nil?
	else
		$pending_ac_state_level = "on"
		$time_last_ac_change_detected = Time.now if $time_last_ac_change_detected.nil?
	end

	if $current_ac_state_level == $pending_ac_state_level
		$pending_ac_state_level = nil
		$time_last_ac_change_detected = nil
	end

	# if ac state has a pending a change for over 10 seconds, set it to current and reset pending state level.
	if !$pending_ac_state_level.nil?
		delayed_transition_time = $time_last_ac_change_detected + 10
		#puts delayed_transition_time
		if delayed_transition_time < Time.now
			$current_ac_state_level = $pending_ac_state_level
			$pending_ac_state_level = nil
			$time_last_ac_change_detected = nil
		end
	end

	$current_ac_state_level = $pending_ac_state_level if $current_ac_state_level.nil?

	print "Variance #{variance}\t\t current:#{$current_ac_state_level},  pending: #{$pending_ac_state_level} \n"
	#print "Count, Sum of Squares, Average #{[count, average_x, sum_of_squares_x, average_y, sum_of_squares_y]}\n"

	return $current_ac_state_level
end

##### Begin Program Execution #####
$sql_client = initializeDatabase
while(true) do
	now = Time.now.to_i

	# Find short motion interval records
	threshold_time = now - $short_motion_interval
	unique_sensors_short, short_interval_results = getRecordsInInterval(threshold_time, 10170400, 10170405)
	
	# Find long motion interval records
	threshold_time = now - $long_motion_interval
	unique_sensors_long, long_interval_results = getRecordsInInterval(threshold_time, 10170400, 10170405)

	# Find ac motion interval records
	threshold_time = now - $ac_change_interval
	unique_sensors_ac, ac_interval_results = getRecordsInInterval(threshold_time,10170500, 19170505)

	# Calculate minimum room occupancy
	analysis = analyzeMotionReadings(unique_sensors_short, short_interval_results)
	count_array = []
	analysis.each do |k,v|
		count_array.push(v['hit_count'] > 0 ? 1 : 0)
	end
	people_count = count_minimum_occupancy_cmil_front(count_array)
	$room_empty = false if people_count > 0

	# check if lights turned on/off
	### Not Working ###
	# $lights_state = check_if_lights_turned_on_or_off(unique_sensors_short, short_interval_results)
	# if($lights_state.nil?)
	# 	puts "Light status unknown"
	# elsif $lights_state
	# 	puts "Lights on"
	# else
	# 	puts "Lights off"
	# end

	#### Get A/C Status ####
	## Detect A/C state using accelerometers
	current_ac_state1 = analyze_air_conditioning_readings([10170504],ac_interval_results)
	# current_ac_state2 = analyze_air_conditioning_readings([XXXXXXXX],ac_interval_results) # No accelerometer in place
	# current_ac_state3 = analyze_air_conditioning_readings([XXXXXXXX],ac_interval_results) # No accelerometer in place
	## Query A/C state using Nest API
	
	#### Logic for turning off A/C ####
	## if room empty and has been empty for 10 min, set target temp = 80F and switch to away mode
	if people_count == 0
		## if zone 1 a/c on or zone 2 a/c on
			## check if empty for $threshold_empty min ## DONE
			# Find long motion interval records
			threshold_time = now - $long_motion_interval
			analysis = analyzeMotionReadings(unique_sensors_long, long_interval_results)
			count_array = []
			analysis.each do |k,v|
				count_array.push(v['hit_count'] > 0 ? 1 : 0)
			end
			$room_empty = true unless count_array.include? 1
			## if room is empty for 10+ min, set target temp = 80F and switch to away mode
			if $room_empty
				puts "room empty"
			else
				puts "room occupied"
				## send a/c off status
				## set target temp = 80F
				## switch to away mode
			end
	else
		## ensure away mode switched off and temp < 76.  If temp > 76, set to 73. 
	end

	record_air_conditioning_decision

	sleep $short_motion_interval 
end