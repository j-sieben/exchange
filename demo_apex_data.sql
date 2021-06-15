-- Als Benutzer APEX_DATA ausfuehren


prompt create HR tables
@?/demo/schema/human_resources/hr_cre.sql

prompt populate HR data
@?/demo/schema/human_resources/hr_popul.sql

prompt modify HR schema
alter table jobs add (
  comm_eligible number(1, 0) default on null 0,
  is_manager number(1, 0) default on null 0);
  
update jobs
   set comm_eligible = 1
 where job_id in ('SA_MAN', 'SA_REP');
 

update jobs
   set is_manager = 1
 where job_id like '%MAN'
    or job_id like '%VP'
    or job_id like '%MGR'
    or job_id like '%PRES';
    
commit;

prompt Create PIT messages
begin
    
  pit_admin.merge_message_group(
    p_pmg_name => 'EMP',
    p_pmg_description => q'^Meldungen für die Mitarbeiter DEMO-App^');

  pit_admin.merge_message(
    p_pms_name => 'EMP_EMAIL_UNIQUE',
    p_pms_pmg_name => 'EMP',
    p_pms_text => q'^Die Email-Adresse "#1#" existiert bereits. Wählen Sie eine eindeutige Mailadresse.^',
    p_pms_description => q'^Die Email-Adresse muss eindeutig sein.^',
    p_pms_pse_id => 30,
    p_pms_pml_name => 'GERMAN',
    p_error_number => -20000);

  pit_admin.merge_message(
    p_pms_name => 'EMP_MANAGER_EXISTS',
    p_pms_pmg_name => 'EMP',
    p_pms_text => q'^Der Mitarbeiter "#1#" existiert nicht^',
    p_pms_description => q'^Es können nur Mitarbeiter gewählt werden, die auch existieren.^',
    p_pms_pse_id => 30,
    p_pms_pml_name => 'GERMAN',
    p_error_number => -20000);

  pit_admin.merge_message(
    p_pms_name => 'EMP_MANAGER_JOB_ELIGIBLE',
    p_pms_pmg_name => 'EMP',
    p_pms_text => q'^Der Mitarbeiter "#1#" ist nicht berechtigt, als Abteilungsleiter eingesetzt zu werden.^',
    p_pms_description => q'^Es können nur Mitarbeiter gewählt werden, die einen geeigneten Beruf besitzen.^',
    p_pms_pse_id => 30,
    p_pms_pml_name => 'GERMAN',
    p_error_number => -20000);

  pit_admin.merge_message(
    p_pms_name => 'EMP_PARAM_REQUIRED',
    p_pms_pmg_name => 'EMP',
    p_pms_text => q'^Feld "#LABEL#" ist ein Pflichtelement.^',
    p_pms_description => q'^Das Eingabefeld ist ein Pflichtelement, bitte tragen Sie einen Wert ein.^',
    p_pms_pse_id => 30,
    p_pms_pml_name => 'GERMAN',
    p_error_number => -20000);

  commit;
  pit_admin.create_message_package;
end;
/


prompt Create package employee
create or replace package employee
  authid definer
as

  /** Method to validate an email address
   * %param  p_row  Instance of an employee record
   * %usage  Is used to assert that an email address is unique
   * %usage  Checks whether email is unique. Two scenarios:
   *         - Employee is unknown and email is not used by any other employee
   *         - Employee is known and email equals its own email (is unchanged)
   *         - Email must not be NULL
   * %raises msg.EMP_EMAIL_UNIQUE_ERR if email is in use
   *         msg.EMP_PARAM_REQUIRED_ERR, Codes
   *         - EMAIL_MISSING if email is missing
   */
  procedure validate_email(
    p_row in employees%rowtype);
    

  /** Method to validate commission settings
   * %param  p_row  Instance of an employee record
   * %usage  Is used to assert that the employee is commission eligible 
   *         and that the commission is within allowed boundaries
   * %usage  Checks wheher a commission is eligible. A commission is eligible if
   *         JOBS metadata set the respective job to commission_eligible
   *         Commission pct is not allowed to be higher than 0.5
   * %raises msg.EMP_EMAIL_UNIQUE_ERR if email is in use
   *         msg.EMP_PARAM_REQUIRED_ERR, Codes
   *         - COMISSION_MISSING if job is eligible but no commission was entered
   */
  procedure validate_commission(
    p_row in employees%rowtype);
  
  
  /** Method to validate whether a manager is an existing employee
   * %param  p_row  Instance of an employee record
   * %usage  Is used to assert that a manager is an existing employee
   * %raises msg.EMP_MANAGER_EXISTS_ERR if manager is not a known employee
   */
  procedure validate_manager(
    p_row in employees%rowtype);
    
    
  /** Method to validate an employee record
   * %param  p_row  Instance of an employee record
   * %usage  Is used to perform various validity checks for an employee
   * %raises msg.EMP_EMAIL_UNIQUE if email is in use
   *         msg.EMP_MANAGER_EXISTS if manager is not a known employee
   *         msg.EMP_PARAM_REQUIRED, Codes
   *         - LAST_NAME_MISSING if last name is missing
   *         - JOB_ID_MISSING if job id is missing
   *         - EMAIL_MISSING if email is missing
   *         - HIRE_DATE_MISSING if hire date is missing
   */
  procedure validate_employee(
    p_row in employees%rowtype);


  /** Method to persist an employee record
   * %param  p_row  Instance of an employee record
   * %usage  Is used to write an employee record to the respective tables
   *         calls @seeVALIDATE_EMPLOYEE
   */
  procedure merge_employee(
    p_row in out nocopy employees%rowtype);


  /** Method to delete an employee
  * %param  p_employee_id  ID of the employee to delete
  * %usage  Is used to delete an employee. If the employee was a manager,
  *         the respective employees are updated to not having a manager anymore
  */
  procedure delete_employee(
    p_employee_id in employees.employee_id%type);

end employee;
/

create or replace package body employee 
as  
  
  procedure validate_email(
    p_row in employees%rowtype)
  as
    l_cur sys_refcursor;
  begin
    pit.enter_optional('validate_email_unique');
    
    pit.assert_not_null(
      p_condition => p_row.email, 
      p_message_name => msg.EMP_PARAM_REQUIRED,
      p_error_code => 'EMAIL_MISSING');
    
    -- Check if email may be used
    open l_cur for 
      select null is_unique
        from employees
       where (employee_id != p_row.employee_id or p_row.employee_id is null)
         and email = p_row.email;
    pit.assert_not_exists(
      p_cursor => l_cur, 
      p_message_name => msg.EMP_EMAIL_UNIQUE, 
      p_msg_args => msg_args(p_row.email));   
     
    pit.leave_optional; 
  end validate_email;
  
  
  procedure validate_commission(
    p_row in employees%rowtype)
  as
  begin
    null;
  end validate_commission;
  
  
  procedure validate_manager(
    p_row in employees%rowtype)
  as
    l_cur sys_refcursor;
  begin
    pit.enter_optional('validate_manager');
    
    if p_row.manager_id is not null then
      -- Check if manager exists in table EMPLOYEES
      open l_cur for
        select null does_exist
          from employees
         where employee_id = p_row.manager_id;
      pit.assert_exists(
        p_cursor => l_cur, 
        p_message_name => msg.EMP_MANAGER_EXISTS, 
        p_msg_args => msg_args(to_char(p_row.manager_id)));
    end if;
     
    pit.leave_optional;
  end validate_manager;
  

  procedure validate_employee(
    p_row in employees%rowtype) 
  as
    l_result number;
  begin
    pit.enter_optional('validate_employee');
    
    pit.assert_not_null(
      p_condition => p_row.last_name, 
      p_message_name => msg.EMP_PARAM_REQUIRED,
      p_error_code => 'LAST_NAME_MISSING');
      
    pit.assert_not_null(
      p_condition => p_row.job_id,
      p_message_name => msg.EMP_PARAM_REQUIRED,
      p_error_code => 'JOB_ID_MISSING');
      
    -- TODO: Check that hire date is a valid date
    pit.assert_not_null(
      p_condition => p_row.hire_date,
      p_message_name => msg.EMP_PARAM_REQUIRED,
      p_error_code => 'HIRE_DATE_MISSING');
    
    validate_email(p_row);
    
    validate_manager(p_row);
     
    pit.leave_optional;
  end validate_employee;
  

  procedure merge_employee(
    p_row in out nocopy employees%rowtype) 
  as
  begin
    pit.enter_mandatory;
  
    validate_employee(p_row);
    
    p_row.employee_id := coalesce(p_row.employee_id, employees_seq.nextval);
    
    merge into employees t
    using (select p_row.employee_id employee_id,
                  p_row.first_name first_name,
                  p_row.last_name last_name,
                  p_row.email email,
                  p_row.phone_number phone_number,
                  p_row.hire_date hire_date,
                  p_row.job_id job_id,
                  p_row.salary salary,
                  p_row.commission_pct commission_pct,
                  p_row.manager_id manager_id,
                  p_row.department_id department_id
             from dual) s
      on (t.employee_id = s.employee_id)
    when matched then update set
         t.first_name = s.first_name,
         t.last_name = s.last_name,
         t.email = s.email,
         t.phone_number = s.phone_number
    when not matched then insert(
           employee_id, first_name, last_name, email, phone_number, hire_date, 
           job_id, salary, commission_pct, manager_id, department_id)
         values (
           s.employee_id, s.first_name, s.last_name, s.email, s.phone_number, s.hire_date, 
           s.job_id, s.salary, s.commission_pct, s.manager_id, s.department_id);
    
    pit.leave_mandatory;
  end merge_employee;
  

  procedure delete_employee(
    p_employee_id in employees.employee_id%type) 
  as
  begin
    pit.enter_mandatory(
      p_params => msg_params(msg_param('p_employee_id', p_employee_id)));
  
    delete from employees
     where employee_id = p_employee_id;
    
    pit.leave_mandatory;
  end delete_employee;

end employee;
/

prompt Grant access on data to APEX_APP
grant execute on employee to apex_app;

declare
  cursor table_cur is
    select table_name
      from user_tables
     where table_name != 'PARAMETER_LOCAL';
begin
  for tbl in table_cur loop
    execute immediate 'grant read on ' || tbl.table_name || ' to apex_app';
  end loop;
end;
/