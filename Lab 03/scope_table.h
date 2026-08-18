#include "symbol_info.h"

class scope_table
{
private:
    int bucket_count;
    int unique_id;
    scope_table *parent_scope = NULL;
    vector<list<symbol_info *>> table;

    int hash_function(string name)
    {
        // sum of ASCII values of all characters, mod bucket_count
        int sum = 0;
        for (char c : name)
        {
            sum += (int)c;
        }
        return sum % bucket_count;
    }

public:
    scope_table() : bucket_count(0), unique_id(0), parent_scope(NULL) {}

    scope_table(int bucket_count, int unique_id, scope_table *parent_scope)
    {
        this->bucket_count = bucket_count;
        this->unique_id = unique_id;
        this->parent_scope = parent_scope;
        table.resize(bucket_count);
    }

    scope_table *get_parent_scope()
    {
        return parent_scope;
    }

    int get_unique_id()
    {
        return unique_id;
    }

    symbol_info *lookup_in_scope(symbol_info *symbol)
    {
        int idx = hash_function(symbol->get_name());
        for (symbol_info *s : table[idx])
        {
            if (s->get_name() == symbol->get_name())
            {
                return s;
            }
        }
        return NULL;
    }

    bool insert_in_scope(symbol_info *symbol)
    {
        // Check if already exists in this scope
        symbol_info *existing = lookup_in_scope(symbol);
        if (existing != NULL)
        {
            // Update the existing symbol's metadata to match the new declaration
            // (the sample implementation updates type even on multiple declaration)
            existing->set_symbol_class(symbol->get_symbol_class());
            existing->set_data_type(symbol->get_data_type());
            existing->set_array_size(symbol->get_array_size());
            return false; // already declared — caller will report error
        }
        int idx = hash_function(symbol->get_name());
        table[idx].push_back(symbol);
        return true;
    }

    bool delete_from_scope(symbol_info *symbol)
    {
        int idx = hash_function(symbol->get_name());
        for (auto it = table[idx].begin(); it != table[idx].end(); it++)
        {
            if ((*it)->get_name() == symbol->get_name())
            {
                table[idx].erase(it);
                return true;
            }
        }
        return false;
    }

    void print_scope_table(ofstream &outlog)
    {
        outlog << "ScopeTable # " + to_string(unique_id) << endl;

        vector<symbol_info*> all_symbols;
        for (int i = 0; i < bucket_count; i++)
        {
            for (symbol_info *s : table[i])
            {
                all_symbols.push_back(s);
            }
        }

        // Iterate through the current scope table and print symbols with all relevant info
        for (int i = 0; i < bucket_count; i++)
        {
            if (!table[i].empty())
            {
                outlog << i << " --> " << endl;
                for (symbol_info *s : table[i])
                {
                    outlog << "< " << s->get_name() << " : " << s->get_type() << " >" << endl;
                    string sc = s->get_symbol_class();
                    if (sc == "variable")
                    {
                        outlog << "Variable" << endl;
                        outlog << "Type: " << s->get_data_type() << endl;
                    }
                    else if (sc == "array")
                    {
                        outlog << "Array" << endl;
                        outlog << "Type: " << s->get_data_type() << endl;
                        outlog << "Size: " << s->get_array_size() << endl;
                    }
                    else if (sc == "function")
                    {
                        outlog << "Function Definition" << endl;
                        outlog << "Return Type: " << s->get_data_type() << endl;
                        outlog << "Number of Parameters: " << s->get_param_count() << endl;
                        // Print parameter details
                        string param_str = "";
                        for (int j = 0; j < (int)s->get_params().size(); j++)
                        {
                            if (j > 0) param_str += ", ";
                            param_str += s->get_params()[j].first + " " + s->get_params()[j].second;
                        }
                        outlog << "Parameter Details: " << param_str << endl;
                    }

                    bool is_last = (!all_symbols.empty() && s == all_symbols.back());
                    if (sc != "function" || is_last)
                    {
                        outlog << endl;
                    }
                }
            }
        }
    }

    ~scope_table()
    {
        // Free all symbol_info objects in this scope
        for (int i = 0; i < bucket_count; i++)
        {
            for (symbol_info *s : table[i])
            {
                delete s;
            }
            table[i].clear();
        }
    }
};