#!/usr/bin/awk -f
#
# Given the recording of a 'typescript' session in which you executed the same
# command multiple times in a loop, this Awk script will pull out the average
# 'real' execution time.
#
# To create such a recording, do something like this:
#	script timing.log
# < and then within the script session: >
#	for i in {1..100}
#	do
#		echo $i
#		time <the command to benchmark>  > /dev/null
#	done
#	exit
#
# To simply pass a bunch of lines for the script to process, you can do this:
#	$ cat << EOD | avg_runtime
#	> real    6m2.234s
#	> real    6m18.084s
#	> real    5m51.548s
#	> real    5m51.080s
#	> real    6m2.858s
#	> EOD


BEGIN {
	tally = 0;
	sumReal = 0;
}
$1 == "real" {
	if ( match($2, "^([0-9]+)m([0-9.]+)s", minsec) ) {
		sumReal += minsec[1] * 60 + minsec[2];
		tally += 1;
	}
	else
		print "Skipping nonmatching line:", $2 >"/dev/stderr";
}
END {
	print  "Total time recordings   : " tally;
	print  "Sum of real time (s)    : " sumReal;
	avg = sumReal / tally;
	min = sprintf("%d", avg / 60);
	printf "Avg of real time (s)    : %.2f\n", avg;
	printf "Avg of real time (m,s)  : %dm%.1fs\n", avg / 60, avg - min * 60;
}
