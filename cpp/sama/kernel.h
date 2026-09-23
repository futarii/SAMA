#pragma once

#include "common.h"
static double full_epanechnikov(const Moment2& m, const Point& q, double h) {
    double qnorm2 = q.x * q.x + q.y * q.y;
    double dot = q.x * m.sum_x + q.y * m.sum_y;
    return static_cast<double>(m.count) -
           (static_cast<double>(m.count) * qnorm2 - 2.0 * dot + m.sum_norm2) / (h * h);
}

static double full_quartic(const Moment2& m, const Point& q, double h) {
    double h2 = h * h;
    double h4 = h2 * h2;
    double q2 = q.x * q.x + q.y * q.y;
    double dot_sum = q.x * m.sum_x + q.y * m.sum_y;
    double sum_d2 = static_cast<double>(m.count) * q2 - 2.0 * dot_sum + m.sum_norm2;
    double quad_sum = q.x * q.x * m.sum_x2 + 2.0 * q.x * q.y * m.sum_xy +
                      q.y * q.y * m.sum_y2;
    double q_sum_p2 = q.x * m.sum_x_norm2 + q.y * m.sum_y_norm2;
    double sum_d4 = static_cast<double>(m.count) * q2 * q2 - 4.0 * q2 * dot_sum +
                    2.0 * q2 * m.sum_norm2 + 4.0 * quad_sum -
                    4.0 * q_sum_p2 + m.sum_norm4;
    return static_cast<double>(m.count) - 2.0 * sum_d2 / h2 + sum_d4 / h4;
}

static double full_kernel_value(const Moment2& m, const Point& q, double h, int kernel_type) {
    if (m.count == 0) return 0.0;
    if (kernel_type == 0) return static_cast<double>(m.count) / h;
    if (kernel_type == 1) return full_epanechnikov(m, q, h);
    if (kernel_type == 2) return full_quartic(m, q, h);
    throw runtime_error("unsupported SBD kernel_type: " + to_string(kernel_type));
}

static double point_kernel_value(double d2, double h, int kernel_type) {
    if (kernel_type == 0) return 1.0 / h;
    if (kernel_type == 1) return 1.0 - d2 / (h * h);
    if (kernel_type == 2) {
        double v = 1.0 - d2 / (h * h);
        return v * v;
    }
    throw runtime_error("unsupported SBD kernel_type: " + to_string(kernel_type));
}

