-- Als Benutzer APEX_APP ausfuehren
declare
  cursor table_cur is
    select table_name
      from all_tables
     where owner = 'APEX_DATA'
       and table_name != 'PARAMETER_LOCAL';
begin
  for tbl in table_cur loop
    begin
      execute immediate 'create or replace synonym ' || tbl.table_name 
                     || ' for apex_data.' || tbl.table_name;
    exception
      when others then
        dbms_output.put_line('Fehler bei ' || tbl.table_name || ': ' || sqlerrm);
    end;      
  end loop;
end;
/

create or replace synonym employee for apex_data.employee;

prompt Create package EMP_UI

create or replace package emp_ui
  authid definer
as

end emp_ui;
/


create or replace package body emp_ui
as

end emp_ui;
/

create or replace view emp_lov_departments as
select department_name d, department_id r
  from departments;
  
create or replace view emp_lob_jobs as
select job_title d, job_id r
  from jobs;
  
  
create or replace view emp_ui_admin_emp as
select e.employee_id, e.last_name, e.first_name, j.job_title, d.department_name
  from employees e
  left join jobs j
    on e.job_id = j.job_id
  left join departments d
    on e.department_id = d.department_id;
    

/*
select utl_dev_apex.get_form_methods(
         p_application_id => 106,
         p_page_id => 3,
         p_static_id => 'EDIT_EMP_FORM',
         p_check_method => 'employee.validate_employee',
         p_insert_method => 'employee.merge_employee',
         p_update_method => 'employee.merge_employee',
         p_delete_method => 'employee.delete_employee')
  from dual;
*/