#include "scope_table.h"

class symbol_table
{
private:
    scope_table *current_scope;
    int bucket_count;
    int current_scope_id;

public:
    symbol_table(int bucket_count)
    {
        this->bucket_count = bucket_count;
        this->current_scope_id = 0;
        this->current_scope = NULL;
    }

    ~symbol_table()
    {
        // Delete all scopes
        while (current_scope != NULL)
        {
            scope_table *parent = current_scope->get_parent_scope();
            delete current_scope;
            current_scope = parent;
        }
    }

    void enter_scope()
    {
        current_scope_id++;
        scope_table *new_scope = new scope_table(bucket_count, current_scope_id, current_scope);
        current_scope = new_scope;
    }

    void exit_scope(ofstream &outlog)
    {
        if (current_scope == NULL) return;
        int id = current_scope->get_unique_id();
        scope_table *parent = current_scope->get_parent_scope();
        delete current_scope;
        current_scope = parent;
        outlog << "Scopetable with ID " << id << " removed" << endl << endl;
    }

    bool insert(symbol_info *symbol)
    {
        if (current_scope == NULL) return false;
        return current_scope->insert_in_scope(symbol);
    }

    symbol_info *lookup(symbol_info *symbol)
    {
        scope_table *temp = current_scope;
        while (temp != NULL)
        {
            symbol_info *found = temp->lookup_in_scope(symbol);
            if (found != NULL)
            {
                return found;
            }
            temp = temp->get_parent_scope();
        }
        return NULL;
    }

    void print_current_scope()
    {
        if (current_scope != NULL)
        {
            // Not used directly but available
        }
    }

    void print_all_scopes(ofstream &outlog)
    {
        outlog << "################################" << endl << endl;
        scope_table *temp = current_scope;
        while (temp != NULL)
        {
            temp->print_scope_table(outlog);
            temp = temp->get_parent_scope();
            if (temp != NULL)
            {
                outlog << endl; // extra blank line between scope tables
            }
        }
        outlog << "################################" << endl << endl;
    }

    // Returns the current scope_id so the syntax analyzer can log "New ScopeTable with ID X created"
    int get_current_scope_id()
    {
        if (current_scope != NULL)
            return current_scope->get_unique_id();
        return 0;
    }

    // Insert a symbol into the parent scope (one level up from current scope)
    bool insert_in_parent_scope(symbol_info *symbol)
    {
        if (current_scope == NULL) return false;
        scope_table *parent = current_scope->get_parent_scope();
        if (parent == NULL) return false;
        return parent->insert_in_scope(symbol);
    }
};