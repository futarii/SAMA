#include "commands.h"

int main(int argc, char** argv) {
    try {
        if (argc < 2) {
            cerr << "usage: kdv_experiment <prepare|sbd|compare> ...\n";
            return 2;
        }
        string cmd = argv[1];
        if (cmd == "prepare") return cmd_prepare(argc, argv);
        if (cmd == "sbd") return cmd_sbd(argc, argv);
        if (cmd == "compare") return cmd_compare(argc, argv);
        cerr << "unknown command: " << cmd << "\n";
        return 2;
    } catch (const exception& ex) {
        cerr << "error: " << ex.what() << "\n";
        return 1;
    }
}
