#pragma once

#include "common.h"
#include "dataset_io.h"
struct Tree2 {
    vector<Point> points;
    vector<int> order;
    vector<Node> nodes;
    int leaf_capacity = 64;
};

static int build_tree2(Tree2& tree, int begin, int end) {
    int idx = static_cast<int>(tree.nodes.size());
    tree.nodes.push_back(Node{});
    Node& node = tree.nodes.back();
    node.begin = begin;
    node.end = end;
    for (int i = begin; i < end; i++) {
        const Point& p = tree.points[tree.order[i]];
        update_bounds(node.box, p);
        node.moment.count++;
        node.moment.sum_x += p.x;
        node.moment.sum_y += p.y;
        double x2 = p.x * p.x;
        double y2 = p.y * p.y;
        double norm2 = x2 + y2;
        node.moment.sum_norm2 += norm2;
        node.moment.sum_x2 += x2;
        node.moment.sum_xy += p.x * p.y;
        node.moment.sum_y2 += y2;
        node.moment.sum_x_norm2 += p.x * norm2;
        node.moment.sum_y_norm2 += p.y * norm2;
        node.moment.sum_norm4 += norm2 * norm2;
    }
    int count = end - begin;
    if (count <= tree.leaf_capacity) {
        tree.nodes[idx].leaf_count = 1;
        return idx;
    }
    double span_x = node.box.xmax - node.box.xmin;
    double span_y = node.box.ymax - node.box.ymin;
    int axis = span_x >= span_y ? 0 : 1;
    int mid = begin + count / 2;
    nth_element(tree.order.begin() + begin, tree.order.begin() + mid, tree.order.begin() + end,
                [&](int lhs, int rhs) {
                    return axis == 0 ? tree.points[lhs].x < tree.points[rhs].x
                                     : tree.points[lhs].y < tree.points[rhs].y;
                });
    int left = build_tree2(tree, begin, mid);
    int right = build_tree2(tree, mid, end);
    tree.nodes[idx].left = left;
    tree.nodes[idx].right = right;
    tree.nodes[idx].leaf_count = tree.nodes[left].leaf_count + tree.nodes[right].leaf_count;
    return idx;
}

