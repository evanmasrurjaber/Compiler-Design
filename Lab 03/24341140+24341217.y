%{

#include "symbol_table.h"

#define YYSTYPE symbol_info*

extern FILE *yyin;
int yyparse(void);
int yylex(void);
extern YYSTYPE yylval;

// Global symbol table with 10 buckets
symbol_table *sym_table;

int lines = 1;

ofstream outlog;
ofstream outerr;

int error_count = 0;

// Current type being declared (int / float / void / char)
string current_type = "";

// List of variable/array entries for the current declaration_list
struct DeclEntry {
    string name;
    bool is_array;
    int array_size;
};
vector<DeclEntry> current_decl_list;

// Argument types for the current function call
vector<string> current_arg_types;

// Parameters for the current function being defined: (param_type, param_name)
vector<pair<string,string>> current_params;

// Flag: true when func_definition has already entered the scope,
// so compound_statement's LCURL action should NOT create a new scope
bool func_scope_entered = false;

// When a function's scope is entered before compound_statement,
// we need to insert the function symbol into the PARENT scope before printing.
// pending_func_sym holds the function symbol to be inserted before print_all_scopes.
symbol_info *pending_func_sym = NULL;

// Name of the current function being defined (for error messages)
string current_func_name = "";

void yyerror(char *s)
{
	outlog<<"At line "<<lines<<" "<<s<<endl<<endl;

    // Reset state on error
    current_decl_list.clear();
    current_params.clear();
    func_scope_entered = false;
    pending_func_sym = NULL;
}

%}

%token IF ELSE FOR WHILE DO BREAK INT CHAR FLOAT DOUBLE VOID RETURN SWITCH CASE DEFAULT CONTINUE PRINTLN ADDOP MULOP INCOP DECOP RELOP ASSIGNOP LOGICOP NOT LPAREN RPAREN LCURL RCURL LTHIRD RTHIRD COMMA SEMICOLON CONST_INT CONST_FLOAT ID

%nonassoc LOWER_THAN_ELSE
%nonassoc ELSE

%%

start : program
	{
		outlog<<"At line no: "<<lines<<" start : program "<<endl<<endl;
		outlog<<"Symbol Table"<<endl<<endl;
		
		// Print the whole symbol table (global scope only remains)
		sym_table->print_all_scopes(outlog);
	}
	;

program : program unit
	{
		outlog<<"At line no: "<<lines<<" program : program unit "<<endl<<endl;
		outlog<<$1->getname()+"\n"+$2->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname()+"\n"+$2->getname(),"program");
	}
	| unit
	{
		outlog<<"At line no: "<<lines<<" program : unit "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"program");
	}
	;

unit : variable_decl
	 {
		outlog<<"At line no: "<<lines<<" unit : variable_decl "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"unit");
	 }
     | func_definition
     {
		outlog<<"At line no: "<<lines<<" unit : func_definition "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"unit");
	 }
     ;

func_definition : type_specifier ID LPAREN param_list RPAREN
		{
			// Build and insert the function symbol into the CURRENT (parent/global) scope
			// before entering the function body scope.
			symbol_info *func_sym = new symbol_info($2->getname(), "ID");
			func_sym->set_symbol_class("function");
			func_sym->set_data_type($1->getname());
			for (auto &p : current_params)
			{
				func_sym->add_param(p.first, p.second);
			}

			// Check for multiple declaration of function
			bool inserted = sym_table->insert(func_sym);
			if (!inserted)
			{
				outerr<<"At line no: "<<lines<<" Multiple declaration of function "<<$2->getname()<<endl<<endl;
				outlog<<"At line no: "<<lines<<" Multiple declaration of function "<<$2->getname()<<endl<<endl;
				error_count++;
				delete func_sym;
			}

			// Now enter scope for function body
			sym_table->enter_scope();
			outlog<<"New ScopeTable with ID "<<sym_table->get_current_scope_id()<<" created"<<endl<<endl;

			// Insert parameters into the new (function body) scope
			for (auto &p : current_params)
			{
				if (!p.second.empty())
				{
					symbol_info *param_sym = new symbol_info(p.second, "ID");
					param_sym->set_symbol_class("variable");
					param_sym->set_data_type(p.first);
					bool param_inserted = sym_table->insert(param_sym);
					if (!param_inserted)
					{
						outerr<<"At line no: "<<lines<<" Multiple declaration of variable "<<p.second<<" in parameter of "<<$2->getname()<<endl<<endl;
						outlog<<"At line no: "<<lines<<" Multiple declaration of variable "<<p.second<<" in parameter of "<<$2->getname()<<endl<<endl;
						error_count++;
						delete param_sym;
					}
				}
			}

			// Tell compound_statement not to create another scope
			func_scope_entered = true;
			current_func_name = $2->getname();
		}
		compound_statement
		{	
			outlog<<"At line no: "<<lines<<" func_definition : type_specifier ID LPAREN param_list RPAREN compound_statement "<<endl<<endl;
			outlog<<$1->getname()<<" "<<$2->getname()<<"("+$4->getname()+")\\n"<<$7->getname()<<endl<<endl;
			
			$$ = new symbol_info($1->getname()+" "+$2->getname()+"("+$4->getname()+")\n"+$7->getname(),"func_def");

			current_params.clear();
			current_func_name = "";
		}
		| type_specifier ID LPAREN RPAREN
		{
			// Build and insert function symbol into current scope before entering body scope
			symbol_info *func_sym = new symbol_info($2->getname(), "ID");
			func_sym->set_symbol_class("function");
			func_sym->set_data_type($1->getname());
			// no params

			bool inserted = sym_table->insert(func_sym);
			if (!inserted)
			{
				outerr<<"At line no: "<<lines<<" Multiple declaration of function "<<$2->getname()<<endl<<endl;
				outlog<<"At line no: "<<lines<<" Multiple declaration of function "<<$2->getname()<<endl<<endl;
				error_count++;
				delete func_sym;
			}

			// Enter scope for function body
			sym_table->enter_scope();
			outlog<<"New ScopeTable with ID "<<sym_table->get_current_scope_id()<<" created"<<endl<<endl;

			current_params.clear();

			// Tell compound_statement not to create another scope
			func_scope_entered = true;
			current_func_name = $2->getname();
		}
		compound_statement
		{
			
			outlog<<"At line no: "<<lines<<" func_definition : type_specifier ID LPAREN RPAREN compound_statement "<<endl<<endl;
			outlog<<$1->getname()<<" "<<$2->getname()<<"()\n"<<$6->getname()<<endl<<endl;
			
			$$ = new symbol_info($1->getname()+" "+$2->getname()+"()\n"+$6->getname(),"func_def");

			current_params.clear();
			current_func_name = "";
		}
 		;

param_list : param_list COMMA type_specifier ID
		{
			outlog<<"At line no: "<<lines<<" param_list : param_list COMMA type_specifier ID "<<endl<<endl;
			outlog<<$1->getname()<<","<<$3->getname()<<" "<<$4->getname()<<endl<<endl;
				
			$$ = new symbol_info($1->getname()+","+$3->getname()+" "+$4->getname(),"param_list");
			
			// Append param info
			current_params.push_back(make_pair($3->getname(), $4->getname()));
		}
		| param_list COMMA type_specifier
		{
			outlog<<"At line no: "<<lines<<" param_list : param_list COMMA type_specifier "<<endl<<endl;
			outlog<<$1->getname()<<","<<$3->getname()<<endl<<endl;
			
			$$ = new symbol_info($1->getname()+","+$3->getname(),"param_list");
			
			// Unnamed param
			current_params.push_back(make_pair($3->getname(), ""));
		}
 		| type_specifier ID
 		{
			outlog<<"At line no: "<<lines<<" param_list : type_specifier ID "<<endl<<endl;
			outlog<<$1->getname()<<" "<<$2->getname()<<endl<<endl;
			
			$$ = new symbol_info($1->getname()+" "+$2->getname(),"param_list");
			
			// First param: reset list then add
			current_params.clear();
			current_params.push_back(make_pair($1->getname(), $2->getname()));
		}
		| type_specifier
		{
			outlog<<"At line no: "<<lines<<" param_list : type_specifier "<<endl<<endl;
			outlog<<$1->getname()<<endl<<endl;
			
			$$ = new symbol_info($1->getname(),"param_list");
			
			// Unnamed param: reset list then add
			current_params.clear();
			current_params.push_back(make_pair($1->getname(), ""));
		}
 		;

compound_statement : LCURL
		{
			// Enter a new scope only if compound_statement is NOT for a function body
			// (for function bodies, scope was already created before this compound_statement)
			if (!func_scope_entered)
			{
				sym_table->enter_scope();
				outlog<<"New ScopeTable with ID "<<sym_table->get_current_scope_id()<<" created"<<endl<<endl;
			}
			else
			{
				// Reset the flag - function scope was already entered
				func_scope_entered = false;
			}
		}
		statements RCURL
		{ 
   		    outlog<<"At line no: "<<lines<<" compound_statement : LCURL statements RCURL "<<endl<<endl;
			outlog<<"{\n"+$3->getname()+"\n}"<<endl<<endl;
			
			$$ = new symbol_info("{\n"+$3->getname()+"\n}","comp_stmnt");
			
            // Print all scopes and exit current scope
            sym_table->print_all_scopes(outlog);
            sym_table->exit_scope(outlog);
 		    }
 		    | LCURL
		{
			if (!func_scope_entered)
			{
				sym_table->enter_scope();
				outlog<<"New ScopeTable with ID "<<sym_table->get_current_scope_id()<<" created"<<endl<<endl;
			}
			else
			{
				func_scope_entered = false;
			}
		}
		RCURL
 		    { 
   		    outlog<<"At line no: "<<lines<<" compound_statement : LCURL RCURL "<<endl<<endl;
			outlog<<"{\n}"<<endl<<endl;
			
			$$ = new symbol_info("{\n}","comp_stmnt");
			
            // Print all scopes and exit current scope
            sym_table->print_all_scopes(outlog);
            sym_table->exit_scope(outlog);
 		    }
 		    ;
 		    
variable_decl : type_specifier declaration_list SEMICOLON
		 {
			outlog<<"At line no: "<<lines<<" variable_decl : type_specifier declaration_list SEMICOLON "<<endl<<endl;
			outlog<<$1->getname()<<" "<<$2->getname()<<";"<<endl<<endl;
			
			$$ = new symbol_info($1->getname()+" "+$2->getname()+";","var_dec");
			
			// Check: void variable type is not allowed
			if (current_type == "void")
			{
				outerr<<"At line no: "<<lines<<" variable type can not be void "<<endl<<endl;
				outlog<<"At line no: "<<lines<<" variable type can not be void "<<endl<<endl;
				error_count++;
				current_decl_list.clear();
			}
			else
			{
				// Insert all variables/arrays from current_decl_list into the symbol table
				for (auto &entry : current_decl_list)
				{
					symbol_info *var_sym = new symbol_info(entry.name, "ID");
					if (entry.is_array)
					{
						var_sym->set_symbol_class("array");
						var_sym->set_data_type(current_type);
						var_sym->set_array_size(entry.array_size);
					}
					else
					{
						var_sym->set_symbol_class("variable");
						var_sym->set_data_type(current_type);
					}

					bool inserted = sym_table->insert(var_sym);
					if (!inserted)
					{
						outerr<<"At line no: "<<lines<<" Multiple declaration of variable "<<entry.name<<endl<<endl;
						outlog<<"At line no: "<<lines<<" Multiple declaration of variable "<<entry.name<<endl<<endl;
						error_count++;
						delete var_sym;
					}
				}
				current_decl_list.clear();
			}
		 }
  		 ;

type_specifier : INT
		{
			outlog<<"At line no: "<<lines<<" type_specifier : INT "<<endl<<endl;
			outlog<<"int"<<endl<<endl;
			
			current_type = "int";
			$$ = new symbol_info("int","type");
	    }
 		| FLOAT
 		{
			outlog<<"At line no: "<<lines<<" type_specifier : FLOAT "<<endl<<endl;
			outlog<<"float"<<endl<<endl;
			
			current_type = "float";
			$$ = new symbol_info("float","type");
	    }
 		| VOID
 		{
			outlog<<"At line no: "<<lines<<" type_specifier : VOID "<<endl<<endl;
			outlog<<"void"<<endl<<endl;
			
			current_type = "void";
			$$ = new symbol_info("void","type");
	    }
		| CHAR
 		{
			outlog<<"At line no: "<<lines<<" type_specifier : CHAR "<<endl<<endl;
			outlog<<"char"<<endl<<endl;
			
			current_type = "char";
			$$ = new symbol_info("char","type");
	    }
 		;

declaration_list : declaration_list COMMA ID
		  {
  		  	outlog<<"At line no: "<<lines<<" declaration_list : declaration_list COMMA ID "<<endl<<endl;
  		  	outlog<<$1->getname()+","<<$3->getname()<<endl<<endl;

  		  	$$ = new symbol_info($1->getname()+","+$3->getname(),"decl_list");

  		  	// Append variable to declaration list
  		  	DeclEntry entry;
  		  	entry.name = $3->getname();
  		  	entry.is_array = false;
  		  	entry.array_size = 0;
  		  	current_decl_list.push_back(entry);
		  }
		  | declaration_list COMMA ID LTHIRD CONST_INT RTHIRD
		  {
  		  	outlog<<"At line no: "<<lines<<" declaration_list : declaration_list COMMA ID LTHIRD CONST_INT RTHIRD "<<endl<<endl;
  		  	outlog<<$1->getname()+","<<$3->getname()<<"["<<$5->getname()<<"]"<<endl<<endl;

  		  	$$ = new symbol_info($1->getname()+","+$3->getname()+"["+$5->getname()+"]","decl_list");

  		  	// Append array to declaration list
  		  	DeclEntry entry;
  		  	entry.name = $3->getname();
  		  	entry.is_array = true;
  		  	entry.array_size = stoi($5->getname());
  		  	current_decl_list.push_back(entry);
		  }
		  | ID
		  {
  		  	outlog<<"At line no: "<<lines<<" declaration_list : ID "<<endl<<endl;
			outlog<<$1->getname()<<endl<<endl;

  		  	$$ = new symbol_info($1->getname(),"decl_list");

  		  	// Reset and start a new declaration list
  		  	current_decl_list.clear();
  		  	DeclEntry entry;
  		  	entry.name = $1->getname();
  		  	entry.is_array = false;
  		  	entry.array_size = 0;
  		  	current_decl_list.push_back(entry);
		  }
		  | ID LTHIRD CONST_INT RTHIRD
		  {
  		  	outlog<<"At line no: "<<lines<<" declaration_list : ID LTHIRD CONST_INT RTHIRD "<<endl<<endl;
			outlog<<$1->getname()<<"["<<$3->getname()<<"]"<<endl<<endl;

  		  	$$ = new symbol_info($1->getname()+"["+$3->getname()+"]","decl_list");

  		  	// Reset and start a new declaration list as array
  		  	current_decl_list.clear();
  		  	DeclEntry entry;
  		  	entry.name = $1->getname();
  		  	entry.is_array = true;
  		  	entry.array_size = stoi($3->getname());
  		  	current_decl_list.push_back(entry);
		  }
		  ;
		  

statements : statement
	   {
    	outlog<<"At line no: "<<lines<<" statements : statement "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"stmnts");
	   }
	   | statements statement
	   {
    	outlog<<"At line no: "<<lines<<" statements : statements statement "<<endl<<endl;
		outlog<<$1->getname()<<"\n"<<$2->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname()+"\n"+$2->getname(),"stmnts");
	   }
	   ;
	   
statement : variable_decl
	  {
    	outlog<<"At line no: "<<lines<<" statement : variable_decl "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"stmnt");
	  }
	  | func_definition
	  {
  		outlog<<"At line no: "<<lines<<" statement : func_definition "<<endl<<endl;
            outlog<<$1->getname()<<endl<<endl;

            $$ = new symbol_info($1->getname(),"stmnt");
	  }
	  | expression_statement
	  {
    	outlog<<"At line no: "<<lines<<" statement : expression_statement "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"stmnt");
	  }
	  | compound_statement
	  {
    	outlog<<"At line no: "<<lines<<" statement : compound_statement "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"stmnt");
	  }
	  | FOR LPAREN expression_statement expression_statement expression RPAREN statement
	  {
    	outlog<<"At line no: "<<lines<<" statement : FOR LPAREN expression_statement expression_statement expression RPAREN statement "<<endl<<endl;
		outlog<<"for("<<$3->getname()<<$4->getname()<<$5->getname()<<")\n"<<$7->getname()<<endl<<endl;
		
		$$ = new symbol_info("for("+$3->getname()+$4->getname()+$5->getname()+")\n"+$7->getname(),"stmnt");
	  }
	  | IF LPAREN expression RPAREN statement %prec LOWER_THAN_ELSE
	  {
    	outlog<<"At line no: "<<lines<<" statement : IF LPAREN expression RPAREN statement "<<endl<<endl;
		outlog<<"if("<<$3->getname()<<")\n"<<$5->getname()<<endl<<endl;
		
		$$ = new symbol_info("if("+$3->getname()+")\n"+$5->getname(),"stmnt");
	  }
	  | IF LPAREN expression RPAREN statement ELSE statement
	  {
    	outlog<<"At line no: "<<lines<<" statement : IF LPAREN expression RPAREN statement ELSE statement "<<endl<<endl;
		outlog<<"if("<<$3->getname()<<")\n"<<$5->getname()<<"\nelse\n"<<$7->getname()<<endl<<endl;
		
		$$ = new symbol_info("if("+$3->getname()+")\n"+$5->getname()+"\nelse\n"+$7->getname(),"stmnt");
	  }
	  | WHILE LPAREN expression RPAREN statement
	  {
    	outlog<<"At line no: "<<lines<<" statement : WHILE LPAREN expression RPAREN statement "<<endl<<endl;
		outlog<<"while("<<$3->getname()<<")\n"<<$5->getname()<<endl<<endl;
		
		$$ = new symbol_info("while("+$3->getname()+")\n"+$5->getname(),"stmnt");
	  }
	  | PRINTLN LPAREN ID RPAREN SEMICOLON
	  {
    	outlog<<"At line no: "<<lines<<" statement : PRINTLN LPAREN ID RPAREN SEMICOLON "<<endl<<endl;
		outlog<<"printf("<<$3->getname()<<");"<<endl<<endl; 

		// Check if the variable used in printf is declared
		symbol_info *lookup_sym = new symbol_info($3->getname(), "ID");
		symbol_info *found = sym_table->lookup(lookup_sym);
		delete lookup_sym;
		if (found == NULL)
		{
			outerr<<"At line no: "<<lines<<" Undeclared variable "<<$3->getname()<<endl<<endl;
			outlog<<"At line no: "<<lines<<" Undeclared variable "<<$3->getname()<<endl<<endl;
			error_count++;
		}
		
		$$ = new symbol_info("printf("+$3->getname()+");","stmnt");
	  }
	  | RETURN expression SEMICOLON
	  {
    	outlog<<"At line no: "<<lines<<" statement : RETURN expression SEMICOLON "<<endl<<endl;
		outlog<<"return "<<$2->getname()<<";"<<endl<<endl;
		
		$$ = new symbol_info("return "+$2->getname()+";","stmnt");
	  }
	  ;
	  
expression_statement : SEMICOLON
			{
				outlog<<"At line no: "<<lines<<" expression_statement : SEMICOLON "<<endl<<endl;
				outlog<<";"<<endl<<endl;
				
				$$ = new symbol_info(";","expr_stmt");
	        }			
			| expression SEMICOLON 
			{
				outlog<<"At line no: "<<lines<<" expression_statement : expression SEMICOLON "<<endl<<endl;
				outlog<<$1->getname()<<";"<<endl<<endl;
				
				$$ = new symbol_info($1->getname()+";","expr_stmt");
	        }
			;
	  
variable : ID 	
      {
	    outlog<<"At line no: "<<lines<<" variable : ID "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;

		// Check if variable is declared
		symbol_info *lookup_sym = new symbol_info($1->getname(), "ID");
		symbol_info *found = sym_table->lookup(lookup_sym);
		delete lookup_sym;

		if (found == NULL)
		{
			outerr<<"At line no: "<<lines<<" Undeclared variable "<<$1->getname()<<endl<<endl;
			outlog<<"At line no: "<<lines<<" Undeclared variable "<<$1->getname()<<endl<<endl;
			error_count++;
		}
		else if (found->get_symbol_class() == "array")
		{
			// Using array without index
			outerr<<"At line no: "<<lines<<" variable is of array type : "<<$1->getname()<<endl<<endl;
			outlog<<"At line no: "<<lines<<" variable is of array type : "<<$1->getname()<<endl<<endl;
			error_count++;
		}

		$$ = new symbol_info($1->getname(),"varbl");
		if (found != NULL && found->get_symbol_class() != "array")
			$$->set_data_type(found->get_data_type());
		// If found is array but used without index, leave data_type as ""
		// so that argument type mismatch checks can detect it.
		
	 }	
	 | ID LTHIRD expression RTHIRD 
	 {
	 	outlog<<"At line no: "<<lines<<" variable : ID LTHIRD expression RTHIRD "<<endl<<endl;
		outlog<<$1->getname()<<"["<<$3->getname()<<"]"<<endl<<endl;

		// Check if variable is declared
		symbol_info *lookup_sym = new symbol_info($1->getname(), "ID");
		symbol_info *found = sym_table->lookup(lookup_sym);
		delete lookup_sym;

		if (found == NULL)
		{
			outerr<<"At line no: "<<lines<<" Undeclared variable "<<$1->getname()<<endl<<endl;
			outlog<<"At line no: "<<lines<<" Undeclared variable "<<$1->getname()<<endl<<endl;
			error_count++;
		}
		else if (found->get_symbol_class() != "array")
		{
			// Using index on non-array variable
			outerr<<"At line no: "<<lines<<" variable is not of array type : "<<$1->getname()<<endl<<endl;
			outlog<<"At line no: "<<lines<<" variable is not of array type : "<<$1->getname()<<endl<<endl;
			error_count++;
		}
		else
		{
			// Variable IS an array - check if the index expression type is integer
			if ($3->get_data_type() != "int")
			{
				outerr<<"At line no: "<<lines<<" array index is not of integer type : "<<$1->getname()<<endl<<endl;
				outlog<<"At line no: "<<lines<<" array index is not of integer type : "<<$1->getname()<<endl<<endl;
				error_count++;
			}
			else if (found->get_data_type() != "int")
			{
				// Array element type is not int (e.g. float array)
				outerr<<"At line no: "<<lines<<" array index is not of integer type : "<<$1->getname()<<endl<<endl;
				outlog<<"At line no: "<<lines<<" array index is not of integer type : "<<$1->getname()<<endl<<endl;
				error_count++;
			}
		}
		
		$$ = new symbol_info($1->getname()+"["+$3->getname()+"]","varbl");
		if (found != NULL)
			$$->set_data_type(found->get_data_type());
	 }
	 ;
	 
expression : logic_expression
	   {
    	outlog<<"At line no: "<<lines<<" expression : logic_expression "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"expr");
		$$->set_data_type($1->get_data_type());
	   }
	   | variable ASSIGNOP logic_expression 	
	   {
    	outlog<<"At line no: "<<lines<<" expression : variable ASSIGNOP logic_expression "<<endl<<endl;
		outlog<<$1->getname()<<"="<<$3->getname()<<endl<<endl;

		$$ = new symbol_info($1->getname()+"="+$3->getname(),"expr");
	   }
	   ;
		
logic_expression : rel_expression
	     {
    	outlog<<"At line no: "<<lines<<" logic_expression : rel_expression "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"lgc_expr");
		$$->set_data_type($1->get_data_type());
	     }	
		 | rel_expression LOGICOP rel_expression 
		 {
    	outlog<<"At line no: "<<lines<<" logic_expression : rel_expression LOGICOP rel_expression "<<endl<<endl;
		outlog<<$1->getname()<<$2->getname()<<$3->getname()<<endl<<endl;
		
		// Result of LOGICOP is integer
		$$ = new symbol_info($1->getname()+$2->getname()+$3->getname(),"lgc_expr");
		$$->set_data_type("int");
	     }	
		 ;
		
rel_expression	: simple_expression
		{
    	outlog<<"At line no: "<<lines<<" rel_expression : simple_expression "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"rel_expr");
		$$->set_data_type($1->get_data_type());
	    }
		| simple_expression RELOP simple_expression
		{
    	outlog<<"At line no: "<<lines<<" rel_expression : simple_expression RELOP simple_expression "<<endl<<endl;
		outlog<<$1->getname()<<$2->getname()<<$3->getname()<<endl<<endl;
		
		// Result of RELOP is integer
		$$ = new symbol_info($1->getname()+$2->getname()+$3->getname(),"rel_expr");
		$$->set_data_type("int");
	    }
		;
		
simple_expression : term
          {
    	outlog<<"At line no: "<<lines<<" simple_expression : term "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"simp_expr");
		$$->set_data_type($1->get_data_type());
		
	      }
		  | simple_expression ADDOP term 
		  {
    	outlog<<"At line no: "<<lines<<" simple_expression : simple_expression ADDOP term "<<endl<<endl;
		outlog<<$1->getname()<<$2->getname()<<$3->getname()<<endl<<endl;
		
		// Result type: if either is float, result is float
		string res_type = "int";
		if ($1->get_data_type() == "float" || $3->get_data_type() == "float")
			res_type = "float";
		$$ = new symbol_info($1->getname()+$2->getname()+$3->getname(),"simp_expr");
		$$->set_data_type(res_type);
	      }
		  ;
		
term :	unary_expression
     {
    	outlog<<"At line no: "<<lines<<" term : unary_expression "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"term");
		$$->set_data_type($1->get_data_type());
		
	 }
     |  term MULOP unary_expression
     {
    	outlog<<"At line no: "<<lines<<" term : term MULOP unary_expression "<<endl<<endl;
		outlog<<$1->getname()<<$2->getname()<<$3->getname()<<endl<<endl;
		
		string res_type = "int";
		if ($1->get_data_type() == "float" || $3->get_data_type() == "float")
			res_type = "float";
		$$ = new symbol_info($1->getname()+$2->getname()+$3->getname(),"term");
		$$->set_data_type(res_type);
		
	 }
     ;

unary_expression : ADDOP unary_expression
		 {
    	outlog<<"At line no: "<<lines<<" unary_expression : ADDOP unary_expression "<<endl<<endl;
		outlog<<$1->getname()<<$2->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname()+$2->getname(),"un_expr");
		$$->set_data_type($2->get_data_type());
	     }
		 | NOT unary_expression 
		 {
    	outlog<<"At line no: "<<lines<<" unary_expression : NOT unary_expression "<<endl<<endl;
		outlog<<"!"<<$2->getname()<<endl<<endl;
		
		$$ = new symbol_info("!"+$2->getname(),"un_expr");
		$$->set_data_type("int");
	     }
		 | factor_info  
		 {
    	outlog<<"At line no: "<<lines<<" unary_expression : factor_info "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"un_expr");
		$$->set_data_type($1->get_data_type());
	     }
		 ;
factor_info : factor	{
	    outlog<<"At line no: "<<lines<<" factor_info : factor "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"fctr_info");
		$$->set_data_type($1->get_data_type());
}	
factor	: variable
    {
	    outlog<<"At line no: "<<lines<<" factor : variable "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"fctr");
		$$->set_data_type($1->get_data_type());
	}
	| ID LPAREN argument_list RPAREN
	{
	    outlog<<"At line no: "<<lines<<" factor : ID LPAREN argument_list RPAREN "<<endl<<endl;
		outlog<<$1->getname()<<"("<<$3->getname()<<")"<<endl<<endl;

		// Look up the function/variable in the symbol table
		symbol_info *func_lookup = new symbol_info($1->getname(), "ID");
		symbol_info *func_sym = sym_table->lookup(func_lookup);
		delete func_lookup;

		string result_type = "int"; // default

		if (func_sym == NULL)
		{
			// Undeclared function
			outerr<<"At line no: "<<lines<<" Undeclared function: "<<$1->getname()<<endl<<endl;
			outlog<<"At line no: "<<lines<<" Undeclared function: "<<$1->getname()<<endl<<endl;
			error_count++;
		}
		else if (func_sym->get_symbol_class() != "function")
		{
			// Calling a non-function as a function
			outerr<<"At line no: "<<lines<<" "<<$1->getname()<<" is not a function"<<endl<<endl;
			outlog<<"At line no: "<<lines<<" "<<$1->getname()<<" is not a function"<<endl<<endl;
			error_count++;
		}
		else
		{
			result_type = func_sym->get_data_type();

			// Check argument count
			int expected_count = func_sym->get_param_count();
			int actual_count = (int)current_arg_types.size();

			if (expected_count != actual_count)
			{
				outerr<<"At line no: "<<lines<<" Inconsistencies in number of arguments in function call: "<<$1->getname()<<endl<<endl;
				outlog<<"At line no: "<<lines<<" Inconsistencies in number of arguments in function call: "<<$1->getname()<<endl<<endl;
				error_count++;
			}
			else
			{
				// Check each argument's type against the function's return type
				for (int i = 0; i < actual_count; i++)
				{
					if (current_arg_types[i] != result_type)
					{
						outerr<<"At line no: "<<lines<<" argument "<<(i+1)<<" type mismatch in function call: "<<$1->getname()<<endl<<endl;
						outlog<<"At line no: "<<lines<<" argument "<<(i+1)<<" type mismatch in function call: "<<$1->getname()<<endl<<endl;
						error_count++;
					}
				}
			}
		}

		// Clear argument type list after checking
		current_arg_types.clear();

		$$ = new symbol_info($1->getname()+"("+$3->getname()+")","fctr");
		$$->set_data_type(result_type);
	}
	| LPAREN expression RPAREN
	{
	   	outlog<<"At line no: "<<lines<<" factor : LPAREN expression RPAREN "<<endl<<endl;
		outlog<<"("<<$2->getname()<<")"<<endl<<endl;
		
		$$ = new symbol_info("("+$2->getname()+")","fctr");
		$$->set_data_type($2->get_data_type());
	}
	| CONST_INT 
	{
	    outlog<<"At line no: "<<lines<<" factor : CONST_INT "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"fctr");
		$$->set_data_type("int");
	}
	| CONST_FLOAT
	{
	    outlog<<"At line no: "<<lines<<" factor : CONST_FLOAT "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"fctr");
		$$->set_data_type("float");
	}
	| variable INCOP 
	{
	    outlog<<"At line no: "<<lines<<" factor : variable INCOP "<<endl<<endl;
		outlog<<$1->getname()<<"++"<<endl<<endl;
		
		$$ = new symbol_info($1->getname()+"++","fctr");
		$$->set_data_type($1->get_data_type());
	}
	| variable DECOP
	{
	    outlog<<"At line no: "<<lines<<" factor : variable DECOP "<<endl<<endl;
		outlog<<$1->getname()<<"--"<<endl<<endl;
		
		$$ = new symbol_info($1->getname()+"--","fctr");
		$$->set_data_type($1->get_data_type());
	}
	;
	
argument_list : arguments
			  {
					outlog<<"At line no: "<<lines<<" argument_list : arguments "<<endl<<endl;
					outlog<<$1->getname()<<endl<<endl;
					
					$$ = new symbol_info($1->getname(),"arg_list");
			  }
			  |
			  {
					outlog<<"At line no: "<<lines<<" argument_list :  "<<endl<<endl;
					outlog<<""<<endl<<endl;
					
					// No arguments - clear the arg types list
					current_arg_types.clear();
					
					$$ = new symbol_info("","arg_list");
			  }
			  ;
	
arguments : arguments COMMA logic_expression
		  {
				outlog<<"At line no: "<<lines<<" arguments : arguments COMMA logic_expression "<<endl<<endl;
				outlog<<$1->getname()<<","<<$3->getname()<<endl<<endl;
				
				// Track this argument's data type
				current_arg_types.push_back($3->get_data_type());
				
				$$ = new symbol_info($1->getname()+","+$3->getname(),"arg");
		  }
	      | logic_expression
	      {
				outlog<<"At line no: "<<lines<<" arguments : logic_expression "<<endl<<endl;
				outlog<<$1->getname()<<endl<<endl;
				
				// First argument - reset and start fresh
				current_arg_types.clear();
				current_arg_types.push_back($1->get_data_type());
				
				$$ = new symbol_info($1->getname(),"arg");
		  }
	      ;
 

%%

int main(int argc, char *argv[])
{
	if(argc != 2) 
	{
		cout<<"Please input file name"<<endl;
		return 0;
	}
	yyin = fopen(argv[1], "r");
	outlog.open("24341140+24341217_log.txt", ios::trunc);
	outerr.open("24341140+24341217_error.txt", ios::trunc);
	
	if(yyin == NULL)
	{
		cout<<"Couldn't open file"<<endl;
		return 0;
	}

	// Create symbol table with 10 buckets
	sym_table = new symbol_table(10);

	// Enter the global (first) scope
	sym_table->enter_scope();
	outlog<<"New ScopeTable with ID "<<sym_table->get_current_scope_id()<<" created"<<endl<<endl;

	yyparse();
	
	outlog<<endl<<"Total lines: "<<lines<<endl;
	outlog<<"Total errors: "<<error_count<<endl;

	outerr<<"Total errors: "<<error_count<<endl;
	
	outlog.close();
	outerr.close();
	
	fclose(yyin);

	delete sym_table;
	
	return 0;
}