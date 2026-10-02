//coded by Feifei Li, contact: lifeifei@cs.fsu.edu

#include "mtimer.h"

MTimer::MTimer()
{
	this->t1=0.0;
	this->t2=0.0;
	this->elapsed=0.0;
	this->usertime=0.0;
	this->systemtime=0.0;
	this->realtime=0.0;
}

MTimer::~MTimer()
{
}

void MTimer::go()
{
	start = std::chrono::high_resolution_clock::now();
}

void MTimer::stop()
{
	end = std::chrono::high_resolution_clock::now();
}

void MTimer::update()
{
       elapsed += std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count() / 1000000000.0;
}

void MTimer::printStat()
{	
    //cout<<endl<<"scan depth: "<<this->n<<" "<<"utopk prob: "<<this->L_rhoi<<endl<<endl;
    //printf("user time=%f \n", usertime);
    //printf("system time=%f \n", systemtime);
    //printf("real time=%f \n", realtime);
    //printf("clock time=%f \n", elapsed); 
    //cout<<"max mem usage(in bytes)= "<<memusage<<endl;
    //cout<<"max mem usage(in KB)= "<<(double)memusage/1024.0<<endl;
    //cout<<"max mem usage(in MB)= "<<(double)memusage/(1024.0*1024.0)<<endl;
   cout<<elapsed;
}
