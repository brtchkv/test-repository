-- PostgreSQL schema and seed data for testing
-- Drop tables if exist (order matters for FKs)
DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS departments;

-- Create departments first (referenced table)
CREATE TABLE departments (
    dept_id SERIAL PRIMARY KEY,
    dept_name VARCHAR(50) NOT NULL,
    manager_name VARCHAR(50),
    budget NUMERIC(10,2) CHECK (budget >= 0)
);

-- Create employees with FK to departments
CREATE TABLE employees (
   emp_id SERIAL PRIMARY KEY,
   emp_name VARCHAR(50) NOT NULL,
   position VARCHAR(50),
   dept_id INT REFERENCES departments(dept_id) ON DELETE SET NULL
);

-- Seed data
INSERT INTO departments (dept_name, manager_name, budget) VALUES
    ('Human Resources', 'Sarah Johnson', 125000.00),
    ('Information Technology', 'Michael Chen', 250000.00),
    ('Marketing', 'Emily Rodriguez', 180000.00);

INSERT INTO employees (emp_name, position, dept_id) VALUES
    ('John Smith', 'HR Specialist', 1),
    ('Alice Brown', 'Software Developer', 2),
    ('David Wilson', 'Marketing Coordinator', 3);
