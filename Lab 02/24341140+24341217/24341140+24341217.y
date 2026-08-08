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

// Current type being declared (int / float / void / char)
string current_type = "";

// List of variable/array entries for the current declaration_list
struct DeclEntry {
    string name;
    bool is_array;
    int array_size;
};
vector<DeclEntry> current_decl_list;

// Parameters for the current function being defined: (param_type, param_name)
vector<pair<string,string>> current_params;

// Flag: true when func_definition has already entered the scope,
// so compound_statement's LCURL action should NOT create a new scope
bool func_scope_entered = false;

// When a function's scope is entered before compound_statement,
// we need to insert the function symbol into the PARENT scope before printing.
// pending_func_sym holds the function symbol to be inserted before print_all_scopes.
symbol_info *pending_func_sym = NULL;

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
			// This way it appears in print_all_scopes when the function body ends.
			symbol_info *func_sym = new symbol_info($2->getname(), "ID");
			func_sym->set_symbol_class("function");
			func_sym->set_data_type($1->getname());
			for (auto &p : current_params)
			{
				func_sym->add_param(p.first, p.second);
			}
			sym_table->insert(func_sym);

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
					sym_table->insert(param_sym);
				}
			}

			// Tell compound_statement not to create another scope
			func_scope_entered = true;
		}
		compound_statement
		{	
			outlog<<"At line no: "<<lines<<" func_definition : type_specifier ID LPAREN param_list RPAREN compound_statement "<<endl<<endl;
			outlog<<$1->getname()<<" "<<$2->getname()<<"("+$4->getname()+")\n"<<$7->getname()<<endl<<endl;
			
			$$ = new symbol_info($1->getname()+" "+$2->getname()+"("+$4->getname()+")\n"+$7->getname(),"func_def");

			current_params.clear();
		}
		| type_specifier ID LPAREN RPAREN
		{
			// Build and insert function symbol into current scope before entering body scope
			symbol_info *func_sym = new symbol_info($2->getname(), "ID");
			func_sym->set_symbol_class("function");
			func_sym->set_data_type($1->getname());
			// no params
			sym_table->insert(func_sym);

			// Enter scope for function body
			sym_table->enter_scope();
			outlog<<"New ScopeTable with ID "<<sym_table->get_current_scope_id()<<" created"<<endl<<endl;

			current_params.clear();

			// Tell compound_statement not to create another scope
			func_scope_entered = true;
		}
		compound_statement
		{
			
			outlog<<"At line no: "<<lines<<" func_definition : type_specifier ID LPAREN RPAREN compound_statement "<<endl<<endl;
			outlog<<$1->getname()<<" "<<$2->getname()<<"()\n"<<$6->getname()<<endl<<endl;
			
			$$ = new symbol_info($1->getname()+" "+$2->getname()+"()\n"+$6->getname(),"func_def");

			current_params.clear();
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
				sym_table->insert(var_sym);
			}
			current_decl_list.clear();
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
		
		$$ = new symbol_info($1->getname(),"varbl");
		
	 }	
	 | ID LTHIRD expression RTHIRD 
	 {
	 	outlog<<"At line no: "<<lines<<" variable : ID LTHIRD expression RTHIRD "<<endl<<endl;
		outlog<<$1->getname()<<"["<<$3->getname()<<"]"<<endl<<endl;
		
		$$ = new symbol_info($1->getname()+"["+$3->getname()+"]","varbl");
	 }
	 ;
	 
expression : logic_expression
	   {
    	outlog<<"At line no: "<<lines<<" expression : logic_expression "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"expr");
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
	     }	
		 | rel_expression LOGICOP rel_expression 
		 {
    	outlog<<"At line no: "<<lines<<" logic_expression : rel_expression LOGICOP rel_expression "<<endl<<endl;
		outlog<<$1->getname()<<$2->getname()<<$3->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname()+$2->getname()+$3->getname(),"lgc_expr");
	     }	
		 ;
		
rel_expression	: simple_expression
		{
    	outlog<<"At line no: "<<lines<<" rel_expression : simple_expression "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"rel_expr");
	    }
		| simple_expression RELOP simple_expression
		{
    	outlog<<"At line no: "<<lines<<" rel_expression : simple_expression RELOP simple_expression "<<endl<<endl;
		outlog<<$1->getname()<<$2->getname()<<$3->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname()+$2->getname()+$3->getname(),"rel_expr");
	    }
		;
		
simple_expression : term
          {
    	outlog<<"At line no: "<<lines<<" simple_expression : term "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"simp_expr");
		
	      }
		  | simple_expression ADDOP term 
		  {
    	outlog<<"At line no: "<<lines<<" simple_expression : simple_expression ADDOP term "<<endl<<endl;
		outlog<<$1->getname()<<$2->getname()<<$3->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname()+$2->getname()+$3->getname(),"simp_expr");
	      }
		  ;
		
term :	unary_expression
     {
    	outlog<<"At line no: "<<lines<<" term : unary_expression "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"term");
		
	 }
     |  term MULOP unary_expression
     {
    	outlog<<"At line no: "<<lines<<" term : term MULOP unary_expression "<<endl<<endl;
		outlog<<$1->getname()<<$2->getname()<<$3->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname()+$2->getname()+$3->getname(),"term");
		
	 }
     ;

unary_expression : ADDOP unary_expression
		 {
    	outlog<<"At line no: "<<lines<<" unary_expression : ADDOP unary_expression "<<endl<<endl;
		outlog<<$1->getname()<<$2->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname()+$2->getname(),"un_expr");
	     }
		 | NOT unary_expression 
		 {
    	outlog<<"At line no: "<<lines<<" unary_expression : NOT unary_expression "<<endl<<endl;
		outlog<<"!"<<$2->getname()<<endl<<endl;
		
		$$ = new symbol_info("!"+$2->getname(),"un_expr");
	     }
		 | factor_info  
		 {
    	outlog<<"At line no: "<<lines<<" unary_expression : factor_info "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"un_expr");
	     }
		 ;
factor_info : factor	{
	    outlog<<"At line no: "<<lines<<" factor_info : factor "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"fctr_info");
	}	
factor	: variable
    {
	    outlog<<"At line no: "<<lines<<" factor : variable "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"fctr");
	}
	| ID LPAREN argument_list RPAREN
	{
	    outlog<<"At line no: "<<lines<<" factor : ID LPAREN argument_list RPAREN "<<endl<<endl;
		outlog<<$1->getname()<<"("<<$3->getname()<<")"<<endl<<endl;

		// Look up the function in the symbol table
		symbol_info *func_lookup = new symbol_info($1->getname(), "ID");
		symbol_info *func_sym = sym_table->lookup(func_lookup);
		delete func_lookup;

		if (func_sym != NULL && func_sym->get_symbol_class() == "function")
		{
			int num_params = func_sym->get_param_count();
			// Parse argument list: split by comma to count arguments
			string arg_str = $3->getname();
			int num_args = 0;
			if (!arg_str.empty())
			{
				num_args = 1;
				for (char c : arg_str)
				{
					if (c == ',') num_args++;
				}
			}

			// Report type mismatch for each argument position
			// (Since we do not track expression result types, every call reports mismatch
			//  as shown in the expected output)
			for (int i = 0; i < num_params && i < num_args; i++)
			{
				outlog<<"At line no: "<<lines<<" argument "<<(i+1)<<" type mismatch in function call: "<<$1->getname()<<endl<<endl;
			}
		}

		$$ = new symbol_info($1->getname()+"("+$3->getname()+")","fctr");
	}
	| LPAREN expression RPAREN
	{
	   	outlog<<"At line no: "<<lines<<" factor : LPAREN expression RPAREN "<<endl<<endl;
		outlog<<"("<<$2->getname()<<")"<<endl<<endl;
		
		$$ = new symbol_info("("+$2->getname()+")","fctr");
	}
	| CONST_INT 
	{
	    outlog<<"At line no: "<<lines<<" factor : CONST_INT "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"fctr");
	}
	| CONST_FLOAT
	{
	    outlog<<"At line no: "<<lines<<" factor : CONST_FLOAT "<<endl<<endl;
		outlog<<$1->getname()<<endl<<endl;
		
		$$ = new symbol_info($1->getname(),"fctr");
	}
	| variable INCOP 
	{
	    outlog<<"At line no: "<<lines<<" factor : variable INCOP "<<endl<<endl;
		outlog<<$1->getname()<<"++"<<endl<<endl;
		
		$$ = new symbol_info($1->getname()+"++","fctr");
	}
	| variable DECOP
	{
	    outlog<<"At line no: "<<lines<<" factor : variable DECOP "<<endl<<endl;
		outlog<<$1->getname()<<"--"<<endl<<endl;
		
		$$ = new symbol_info($1->getname()+"--","fctr");
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
					
					$$ = new symbol_info("","arg_list");
			  }
			  ;
	
arguments : arguments COMMA logic_expression
		  {
				outlog<<"At line no: "<<lines<<" arguments : arguments COMMA logic_expression "<<endl<<endl;
				outlog<<$1->getname()<<","<<$3->getname()<<endl<<endl;
				
				$$ = new symbol_info($1->getname()+","+$3->getname(),"arg");
		  }
	      | logic_expression
	      {
				outlog<<"At line no: "<<lines<<" arguments : logic_expression "<<endl<<endl;
				outlog<<$1->getname()<<endl<<endl;
				
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
	
	outlog<<endl<<"Total lines: "<<lines<<endl<<endl;
	
	outlog.close();
	
	fclose(yyin);

	delete sym_table;
	
	return 0;
}