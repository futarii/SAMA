#pragma once

#include "common.h"

bool file_exists(const string& path);
vector<double> parse_numbers(const string& line);
void update_bounds(Bounds& b, const Point& p);
Dataset load_dataset(const string& path);
void write_header_dataset(const Dataset& ds, const string& path);
void translate_to_origin(Dataset& ds);
Bounds translated_box(const Bounds& box, double ox, double oy);
double scott_bandwidth(const vector<Point>& pts, double factor);
