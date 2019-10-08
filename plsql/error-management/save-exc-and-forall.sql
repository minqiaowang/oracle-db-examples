/*
Add the SAVE EXCEPTIONS clause to your FORALL statement when you want the 
PL/SQL runtime engine to execute all DML statements generated by the FORALL, 
even if one or more than fail with an error. If you use INDICES OF, you will 
need to take some care to find your way back to the offending statement.
*/

CREATE TABLE employees 
AS 
   SELECT * FROM hr.employees ;

-- Name that -24381! (once)
/*
PL/SQL raises ORA-24381 if at least one statement failed in a FORALL that 
uses SAVE EXCEPTION. It is best to handle exceptions by name, but this error 
is not named in STANDARD. So we do it ourselves!
*/

CREATE OR REPLACE PACKAGE std_errs  
IS  
   failure_in_forall   EXCEPTION;  
   PRAGMA EXCEPTION_INIT (failure_in_forall, -24381);  
END; 
/

-- First, Without SAVE EXCEPTIONS
/*
You can't update a first_name to a string of 1000 or 3000 bytes. But without 
SAVE EXCEPTIONS we never get past the third element in the bind array. 
The employees table has 107 rows. How many were updated?
*/
DECLARE  
   TYPE namelist_t IS TABLE OF VARCHAR2 (5000);  
  
   enames_with_errors   namelist_t  
      := namelist_t ('ABC',  
                     'DEF',  
                     RPAD ('BIGBIGGERBIGGEST', 1000, 'ABC'),  
                     'LITTLE',  
                     RPAD ('BIGBIGGERBIGGEST', 3000, 'ABC'),  
                     'SMITHIE');  
BEGIN  
   FORALL indx IN 1 .. enames_with_errors.COUNT  
      UPDATE employees  
         SET first_name = enames_with_errors (indx);  
  
   ROLLBACK;  
EXCEPTION  
   WHEN OTHERS  
   THEN  
      DBMS_OUTPUT.put_line (  
         'Updated ' || SQL%ROWCOUNT || ' rows.');  
      DBMS_OUTPUT.put_line (SQLERRM);  
      ROLLBACK;  
END; 
/

-- Now With SAVE EXCEPTIONS
/*
Execute every generated statement no matter how of them fail, please! 
Now how many rows were updated? Notice that with SAVE EXCEPTIONS in place, 
I can take advantage of SQL%BULK_EXCEPTIONS to see how statements failed, 
and which ones, and with which error. Can you see, however, the difference 
between the error information displayed in the previous step and this one?
*/

DECLARE  
   TYPE namelist_t IS TABLE OF VARCHAR2 (5000);  
  
   enames_with_errors   namelist_t  
      := namelist_t ('ABC',  
                     'DEF',  
                     RPAD ('BIGBIGGERBIGGEST', 1000, 'ABC'),  
                     'LITTLE',  
                     RPAD ('BIGBIGGERBIGGEST', 3000, 'ABC'),  
                     'SMITHIE');  
BEGIN  
   FORALL indx IN 1 .. enames_with_errors.COUNT SAVE EXCEPTIONS  
      UPDATE employees  
         SET first_name = enames_with_errors (indx);  
  
   ROLLBACK;  
EXCEPTION  
   WHEN std_errs.failure_in_forall  
   THEN  
      DBMS_OUTPUT.put_line (SQLERRM);  
      DBMS_OUTPUT.put_line (  
         'Updated ' || SQL%ROWCOUNT || ' rows.');  
  
      FOR indx IN 1 .. SQL%BULK_EXCEPTIONS.COUNT  
      LOOP  
         DBMS_OUTPUT.put_line (  
               'Error '  
            || indx  
            || ' occurred on index '  
            || SQL%BULK_EXCEPTIONS (indx).ERROR_INDEX  
            || ' attempting to update name to "'  
            || enames_with_errors (  
                  SQL%BULK_EXCEPTIONS (indx).ERROR_INDEX)  
            || '"');  
         DBMS_OUTPUT.put_line (  
               'Oracle error is '  
            || SQLERRM (  
                  -1 * SQL%BULK_EXCEPTIONS (indx).ERROR_CODE));  
      END LOOP;  
  
      ROLLBACK;  
END; 
/

-- Now Explore SAVE EXCEPTIONS with Sparse Bind Arrays
/*
If the array that drives the FORALL statement (the bind array) is not 
dense and you use INDICES OF, you can run into some complications.
*/

CREATE TABLE plch_employees  
(  
   employee_id   INTEGER,  
   last_name     VARCHAR2 (100),  
   salary        NUMBER (8, 0)  
) ;

BEGIN 
   INSERT INTO plch_employees 
        VALUES (100, 'Ninhursag ', 1000000); 
 
   INSERT INTO plch_employees 
        VALUES (200, 'Inanna', 1000000); 
 
   INSERT INTO plch_employees 
        VALUES (300, 'Enlil', 1000000); 
 
   COMMIT; 
END; 
/

-- INDICES OF - BETWEEN - Complications!
/*
INDICES OF is a great feature: you can use it when your bind array is not 
densely filled. And you can use BETWEEN to further finesse which elements 
in the bind array are used to generate statements. But then it is a challenge 
to correlate the SQL%BULK_EXCEPTIONS ERROR_INDEX value back to the right 
index value in the bind array! Which index values do you think will be displayed here?
*/

DECLARE  
   TYPE employee_aat IS TABLE OF employees.employee_id%TYPE  
      INDEX BY PLS_INTEGER;  
  
   l_employees         employee_aat;  
BEGIN  
   l_employees (1) := 100;  
   l_employees (2) := 200;  
   l_employees (3) := 300;  
   l_employees (4) := 200;  
   l_employees (5) := 100;  
  
   FORALL l_index IN INDICES OF l_employees BETWEEN 3 AND 5  
     SAVE EXCEPTIONS  
      UPDATE plch_employees  
         SET salary =  
                  salary  
                * CASE employee_id WHEN 200 THEN 1 ELSE 100 END  
       WHERE employee_id = l_employees (l_index);  
EXCEPTION  
   WHEN std_errs.failure_in_forall  
   THEN  
      DBMS_OUTPUT.put_line ('Errors:');  
  
      FOR indx IN 1 .. SQL%BULK_EXCEPTIONS.COUNT  
      LOOP  
         DBMS_OUTPUT.put_line (  
            SQL%BULK_EXCEPTIONS (indx).ERROR_INDEX);  
      END LOOP;  
  
      ROLLBACK;  
END; 
/

-- Correlate ERROR INDEX Back to Bind Array
/*
Now I offer a helpful utility, bind_array_index_for, that figures out the 
actual index value in the bind array from the ERROR_INDEX value and the 
start/end values in the INDICES OF BETWEEN's clause.
*/

DECLARE  
   TYPE employee_aat IS TABLE OF employees.employee_id%TYPE  
      INDEX BY PLS_INTEGER;  
  
   l_employees   employee_aat;  
  
   FUNCTION bind_array_index_for (  
      bind_array_in    IN employee_aat,  
      error_index_in   IN PLS_INTEGER,  
      start_in         IN PLS_INTEGER DEFAULT NULL,  
      end_in           IN PLS_INTEGER DEFAULT NULL)  
      RETURN PLS_INTEGER  
   IS  
      l_index   PLS_INTEGER  
                   := NVL (start_in, bind_array_in.FIRST);  
   BEGIN  
      FOR indx IN 1 .. error_index_in - 1  
      LOOP  
         l_index := bind_array_in.NEXT (l_index);  
      END LOOP;  
  
      RETURN l_index;  
   END;  
BEGIN  
   BEGIN  
      l_employees (1) := 100;  
      l_employees (100) := 200;  
      l_employees (500) := 300;  
  
      FORALL l_index IN INDICES OF l_employees SAVE EXCEPTIONS  
         UPDATE plch_employees  
            SET salary =  
                     salary  
                   * CASE employee_id  
                        WHEN 200 THEN 1  
                        ELSE 100  
                     END  
          WHERE employee_id = l_employees (l_index);  
   EXCEPTION  
      WHEN failure_in_forall  
      THEN  
         DBMS_OUTPUT.put_line ('Errors:');  
  
         FOR indx IN 1 .. SQL%BULK_EXCEPTIONS.COUNT  
         LOOP  
            DBMS_OUTPUT.put_line (  
               SQL%BULK_EXCEPTIONS (indx).ERROR_INDEX);  
            DBMS_OUTPUT.put_line (  
               bind_array_index_for (  
                  l_employees,  
                  SQL%BULK_EXCEPTIONS (indx).ERROR_INDEX));  
         END LOOP;  
  
         ROLLBACK;  
   END;  
  
   BEGIN  
      l_employees (1) := 100;  
      l_employees (2) := 200;  
      l_employees (3) := 300;  
      l_employees (4) := 200;  
      l_employees (5) := 100;  
  
      FORALL l_index IN INDICES OF l_employees BETWEEN 3 AND 5  
        SAVE EXCEPTIONS  
         UPDATE plch_employees  
            SET salary =  
                     salary  
                   * CASE employee_id  
                        WHEN 200 THEN 1  
                        ELSE 100  
                     END  
          WHERE employee_id = l_employees (l_index);  
   EXCEPTION  
      WHEN std_errs.failure_in_forall  
      THEN  
         DBMS_OUTPUT.put_line ('Errors:');  
  
         FOR indx IN 1 .. SQL%BULK_EXCEPTIONS.COUNT  
         LOOP  
            DBMS_OUTPUT.put_line (  
               SQL%BULK_EXCEPTIONS (indx).ERROR_INDEX);  
            DBMS_OUTPUT.put_line (  
               bind_array_index_for (  
                  l_employees,  
                  SQL%BULK_EXCEPTIONS (indx).ERROR_INDEX,  
                  3,  
                  5));  
         END LOOP;  
  
         ROLLBACK;  
   END;  
END; 
/

