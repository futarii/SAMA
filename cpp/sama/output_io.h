#pragma once

#include "common.h"

GridInfo make_grid(const Dataset& ds, int rows, int cols);
void write_values(const string& path, const GridInfo& grid, const vector<double>& values);
vector<double> read_values_only(const string& path, int expected);
unsigned char clamp_byte(double v);
void parse_hex_color(const char* hex, unsigned char& r, unsigned char& g, unsigned char& b);
void coreset_threshold_color(double percent, unsigned char& r, unsigned char& g, unsigned char& b);
void write_ppm(const string& path, int rows, int cols, const vector<double>& values,
               double min_v, double max_v, bool absolute = false);
void write_html_viewer(const string& path, const string& title,
                       const string& a_img, const string& b_img, const string& diff_img);
