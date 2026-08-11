#include<bits/stdc++.h>
using namespace std;

class symbol_info
{
private:
    string name;
    string type;

    // symbol_class: "variable", "array", "function"
    string symbol_class;

    // data_type / return type: "int", "float", "void", "char"
    string data_type;

    // For arrays: size of the array
    int array_size;

    // For functions: list of (param_type, param_name) pairs
    vector<pair<string,string>> params;

public:
    symbol_info(string name, string type)
    {
        this->name = name;
        this->type = type;
        this->symbol_class = "";
        this->data_type = "";
        this->array_size = 0;
    }

    string get_name()
    {
        return name;
    }

    // alias used in syntax_analyzer.y
    string getname()
    {
        return name;
    }

    string get_type()
    {
        return type;
    }

    void set_name(string name)
    {
        this->name = name;
    }

    void set_type(string type)
    {
        this->type = type;
    }

    string get_symbol_class()
    {
        return symbol_class;
    }

    void set_symbol_class(string sc)
    {
        this->symbol_class = sc;
    }

    string get_data_type()
    {
        return data_type;
    }

    void set_data_type(string dt)
    {
        this->data_type = dt;
    }

    int get_array_size()
    {
        return array_size;
    }

    void set_array_size(int sz)
    {
        this->array_size = sz;
    }

    void add_param(string ptype, string pname)
    {
        params.push_back(make_pair(ptype, pname));
    }

    vector<pair<string,string>>& get_params()
    {
        return params;
    }

    int get_param_count()
    {
        return (int)params.size();
    }

    ~symbol_info()
    {
        // no dynamic allocation to clean up
    }
};