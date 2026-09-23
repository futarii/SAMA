//coded by Feifei Li, contact: lifeifei@cs.fsu.edu

#include <stdio.h>
#include <stdlib.h>
#include <iostream>
#include <chrono>

using namespace::std;

class MTimer{
		public:
	MTimer();
 	~MTimer();
	void printStat();
	void go();
	void stop();
	void update();

		public:
	double t1, t2;
	std::chrono::high_resolution_clock::time_point start, end;
	double elapsed;
	double usertime;
	double systemtime;
	double realtime;
};

