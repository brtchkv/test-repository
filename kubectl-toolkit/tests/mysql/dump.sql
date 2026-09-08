SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS employees;
CREATE TABLE employees (
   emp_id INT PRIMARY KEY AUTO_INCREMENT,
   emp_name VARCHAR(50) NOT NULL,
   position VARCHAR(50),
   dept_id INT,
   FOREIGN KEY (dept_id) REFERENCES departments(dept_id) ON DELETE SET NULL
);

DROP TABLE IF EXISTS departments;
CREATE TABLE departments (
    dept_id INT PRIMARY KEY AUTO_INCREMENT,
    dept_name VARCHAR(50) NOT NULL,
    manager_name VARCHAR(50),
    budget DECIMAL(10,2),
    CONSTRAINT chk_budget CHECK (budget >= 0)
);


-- Insert data into departments
INSERT INTO departments (dept_name, manager_name, budget) VALUES
    ('Human Resources', 'Sarah Johnson', 125000.00),
    ('Information Technology', 'Michael Chen', 250000.00),
    ('Marketing', 'Emily Rodriguez', 180000.00);

-- Insert data into employees
INSERT INTO employees (emp_name, position, dept_id) VALUES
    ('John Smith', 'HR Specialist', 1),
    ('Alice Brown', 'Software Developer', 2),
    ('David Wilson', 'Marketing Coordinator', 3);

SET FOREIGN_KEY_CHECKS = 1;