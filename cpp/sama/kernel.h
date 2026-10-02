#pragma once

#include "common.h"

double full_epanechnikov(const Moment2& m, const Point& q, double h);
double full_quartic(const Moment2& m, const Point& q, double h);
double full_kernel_value(const Moment2& m, const Point& q, double h, int kernel_type);
double point_kernel_value(double d2, double h, int kernel_type);
