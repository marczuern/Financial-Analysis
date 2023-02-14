-- -------------------------------------- --
-- -------------------------------------- --
--    A2: Case - Rosas Palas Franchise    --
--               by Trio 7                --
-- -------------------------------------- --

-- Use the H_Accounting Datatable
USE H_Accounting;


-- Create a procedure to calculate all relevant values for each year, each company_id for the Profit and Loss Statement and the Balance Sheet
-- To run a new proedure, drop the old one in case it exists
DROP PROCEDURE IF EXISTS H_Accounting.mzurn;
DELIMITER $$

-- create a new procedure to be able to call it later
CREATE PROCEDURE H_Accounting.mzurn()
BEGIN
-- use the mzurn_tmp table
	DROP TABLE IF EXISTS H_Accounting.mzurn_tmp;

-- Create the mzurn_tmp table with the following columns for Profit and Loss Statement and the Balance Sheet
	CREATE TABLE H_Accounting.mzurn_tmp
		(is_balance_sheet_section tinyint, 
        company_id int, 
		`year` int, 
		statement_section_order int, 
		statement_section varchar(50),
		balance float);
  
-- The following part calculates the values and stores them into the database
	INSERT INTO H_Accounting.mzurn_tmp (is_balance_sheet_section, company_id, `year`, statement_section_order, statement_section, balance)
-- Starting with the Profit and Loss statement, store every value as positive if it is a kind of income or negative if it is kind of an expense
	SELECT * FROM (
    SELECT s.is_balance_sheet_section, s.company_id, YEAR(entry_date) as year, s.statement_section_order, s.statement_section,
		CASE 
			WHEN s.statement_section_order IN (1,4,5,11) THEN IFNULL(sum(debit),0)
			WHEN s.statement_section_order IN (2,3,6,7,8,9,10,12,13) THEN IFNULL(sum(debit),0)*-1
        END AS balance 
-- Join all datatables together based on their primary and foreign keys to categorize by year, company, statement section and order
	FROM account AS a
	JOIN statement_section AS s
		ON a.profit_loss_section_id = s.statement_section_id
	JOIN journal_entry_line_item AS jel
		ON a.account_id = jel.account_id
	JOIN journal_entry AS je
		ON je.journal_entry_id = jel.journal_entry_id
-- Only include profit and loss sections, no balance sheet section
	WHERE profit_loss_section_id != 0
-- do not include cancelled transactions
		AND je.cancelled = 0
-- aggregate all values as sum by the following categories
	GROUP BY s.is_balance_sheet_section, s.company_id, year, s.statement_section_order, s.statement_section) as PL
-- append the balance sheet data to the temporary table
    UNION
-- calculate the balance sheet as debit - credit values
    (SELECT s.is_balance_sheet_section, s.company_id, YEAR(entry_date) as year, s.statement_section_order, s.statement_section, SUM(IFNULL(debit, 0) - IFNULL(credit, 0)) AS balance
	FROM journal_entry as je
-- Join all datatables together based on their primary and foreign keys to categorize by year, company, statement section and order
	JOIN journal_entry_line_item as jeli
		ON je.journal_entry_id = jeli.journal_entry_id
	JOIN account as a
		ON jeli.account_id = a.account_id
	JOIN statement_section as s
		ON a.balance_sheet_section_id = s.statement_section_id
-- do not include cancelled transactions
	WHERE  	je.cancelled = 0
-- Only include balance sheet sections, no proft and loss sections
		AND s.statement_section_order != 0
-- aggregate all values as sum by the following categories
	GROUP BY s.is_balance_sheet_section, s.company_id, YEAR(entry_date), s.statement_section_order, s.statement_section);
END $$
DELIMITER ;

-- run the procedure one, to store all values to the database
CALL H_Accounting.mzurn();
-- SELECT * FROM H_Accounting.mzurn_tmp;

/*
-- ----------------------------------- --
-- Calculate the Profit Loss Statement --
-- ----------------------------------- --
enter the year and the company as attribute in the WHERE clause
at the end of the query.
Were aware, that there is only data to one company,
but tried to make the query work as generally as possible
*/

-- Only show the statement section and the balance
SELECT totTable.category as Profit_Loss_Statement, totTable.balance 
FROM (
-- Show all sections from the temporary table to sum them to GROSS PROFIT later, also add concat to format the output a little. 
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, FORMAT(balance,2) as balance 
FROM H_Accounting.mzurn_tmp
-- FILTER all sections to see what sums up to GROSS PROFIT
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9)
-- exclude sections from the balance sheet
	AND is_balance_sheet_section = 0

UNION ALL

-- Calculate the GROSS PROFIT by unioning an additional line
SELECT company_id, year, 9.5 , 'GROSS PROFIT', FORMAT(sum(balance),2)
FROM H_Accounting.mzurn_tmp
-- FILTER all sections to sum them to GROSS PROFIT
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9)
-- exclude sections from the balance sheet
	AND is_balance_sheet_section = 0
-- summarize by the company_id and the year
GROUP BY company_id, year

UNION ALL

-- Show all sections that are atted to PROFIT BEFORE TAXES, also add concat to format the output a little. 
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, FORMAT(balance,2) as balance 
FROM H_Accounting.mzurn_tmp
-- Only show the other expenses and other income
WHERE statement_section_order IN (10,11)
-- exclude sections from the balance sheet
	AND is_balance_sheet_section = 0

UNION ALL

-- Calculate the PROFIT BEFORE TAXES by unioning an additional line
SELECT company_id, year, 11.5 , 'PROFIT BEFORE TAXES', FORMAT(sum(balance),2)
FROM H_Accounting.mzurn_tmp
-- FILTER all sections to sum them to GROSS PROFIT
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9,10,11)
-- exclude sections from the balance sheet
	AND is_balance_sheet_section = 0
GROUP BY company_id, year

UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, FORMAT(balance,2) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (12,13)
-- exclude sections from the balance sheet
	AND is_balance_sheet_section = 0

UNION ALL

-- Calculate the PNET PROFIT by summarizing all categories without a filter, this is possible because the balance has a sign for positive and negative
SELECT company_id, year, 13.5 , 'NET PROFIT', FORMAT(sum(balance),2)
FROM H_Accounting.mzurn_tmp
-- exclude sections from the balance sheet
WHERE is_balance_sheet_section = 0
GROUP BY company_id, year

UNION ALL 

SELECT company_id, year, 400 , 'Gross Margin Ratio %',  FORMAT(cod.balance/sum(rev.balance),2)
FROM H_Accounting.mzurn_tmp as rev
JOIN (	SELECT company_id, year, sum(-1*balance) as balance
		FROM H_Accounting.mzurn_tmp
		WHERE is_balance_sheet_section = 0
			AND statement_section_order IN (7)
		GROUP BY company_id, year) as cod
USING (company_id, year)
WHERE is_balance_sheet_section = 0
AND statement_section_order IN (1)
GROUP BY company_id, `year`) 
as totTable
-- FILTER BY the selected year and the company id
	WHERE year = 2016
	AND company_id = 1
-- ORDER the outpit by statement_section_order to keep the sum values in right order 
ORDER BY statement_section_order;

/*
-- --------------------------- --
-- Calculate the Balance Sheet --
-- --------------------------- --
enter the year and the company as attribute in the WHERE clause
at the end of the query.
*/

-- Only show the statement section as category and the balance
SELECT totTable.category as 'Balance Sheet', totTable.balance 
FROM (
-- add additional describing lines to balance sheet like ASSETS
SELECT -1000 as company_id, 0.1 as year, 0.0 as statement_section_order, '' as Category, '' as balance
UNION ALL
SELECT -1000, 0, 0.1, 'ASSETS', ''
UNION ALL
-- Show all sections from the temporary table to sum them to TOTAL ASSETS later, also add concat to format the output a little. 
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, FORMAT(balance,2) as balance 
FROM H_Accounting.mzurn_tmp
-- Only show Assets
WHERE statement_section_order IN (1,2,3)
-- exclude sections from the profit loss statement
	AND is_balance_sheet_section = 1

UNION ALL

SELECT company_id, year, 3.6, 'TOTAL ASSETS' as category, FORMAT(sum(balance),2) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3)
-- exclude sections from the profit loss statement
	AND is_balance_sheet_section = 1
GROUP BY company_id, year

UNION ALL

-- Adding some lines for design an clearity
SELECT -1000, 0, 3.65, '', ''
UNION ALL

SELECT -1000, 0, 3.7, 'LIABILITIES AND SHAREHOLDERS EQUITY', ''
UNION ALL

-- Show all sections from the temporary table to sum them to TOTAL LIABILITIES later. 
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, FORMAT(-1*balance,2) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6)
-- exclude sections from the profit loss statement
	AND is_balance_sheet_section = 1
    
UNION ALL

-- Summarize the TOTAL LIABILITES
SELECT company_id, year, 6.5, 'TOTAL LIABILITIES' as category, FORMAT(-1*sum(balance),2) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6)
-- exclude sections from the profit loss statement
	AND is_balance_sheet_section = 1
GROUP BY company_id, year

UNION ALL
SELECT -1000, 0, 6.6, 'SHAREHOLDERS EQUITY', ''
UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, FORMAT(-1*balance,2) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (7)
-- exclude sections from the profit loss statement
	AND is_balance_sheet_section = 1
    
UNION ALL

-- Summarize the TOTAL LIABILITES AND SHAREHOLDERS EQUITY as overall group to match the ASSETS
SELECT company_id, year, 7.5, 'TOTAL LIABILITIES AND SHAREHOLDERS EQUITY' as category, FORMAT(-1*sum(balance),2) as balance 
FROM H_Accounting.mzurn_tmp
-- Only include the "right"-side of the balance sheet by selecting the sections 4,5,6,7
WHERE statement_section_order IN (4,5,6,7)
-- exclude sections from the profit loss statement
	AND is_balance_sheet_section = 1
GROUP BY company_id, year
) as totTable
-- Enter the company_id and year, but leave -1000 and 0 to keep the order and shape of the balance sheet
WHERE company_id IN (1,-1000)
	AND year IN (2015, 0)
ORDER BY statement_section_order
;

/*
-- -------------------------- --
-- Demonstrate that A = L + E --
-- -------------------------- --
*/
-- SELECT all companies, years and their sums of balance sheets. To validate the rule A = L + E, extend with a case statemnt to prove
SELECT company_id, year, a.balance as TOTAL_ASSETS, le.balance as TOTAL_LIABILITIES_AND_SHAREHOLDERS_EQUITY,
	CASE 
		WHEN FORMAT(a.balance,0) = FORMAT(le.balance,0) THEN 'A = L + E'
		WHEN FORMAT(a.balance,0) != FORMAT(le.balance,0) THEN 'A != L + E'
	END as BalanceCheck
FROM (	SELECT company_id, year, 'TOTAL ASSETS' as category, FORMAT(sum(balance),2) as balance 
		FROM H_Accounting.mzurn_tmp
		WHERE statement_section_order IN (1,2,3)
			AND is_balance_sheet_section = 1
		GROUP BY company_id, year) as a
-- JOIN Assets with Liablities to have the balances in the same row, not the same column
JOIN (	SELECT company_id, year, 'TOTAL LIABILITIES AND SHAREHOLDERS EQUITY' as category, FORMAT(-1*sum(balance),2) as balance 
		FROM H_Accounting.mzurn_tmp
		WHERE statement_section_order IN (4,5,6,7)
			AND is_balance_sheet_section = 1
		GROUP BY company_id, year
		ORDER BY year) as le
-- JOIN using the company_id and year, to fully match all further possible data
USING (company_id, year);


/*
-- ---------------------------------------------------------------------------- --
-- Show the % change vs. the previous year for every major line item on the P&L --
-- ---------------------------------------------------------------------------- --
*/
-- SELECT all balances and calculate their ratios in comparison to the previous year
-- Starting off with all sections and left joining each year to it, to have a complete table.
-- The calculation is the same as above for the Profit and Loss, but we removed the comments to make the code shorter, all comments are above

SELECT statement_section as 'Profit Loss Statement', FORMAT(IFNULL(t2015.balance,0),2) as b2015, FORMAT(IFNULL(t2016.balance,0),2) as b2016, 
	FORMAT(IFNULL(t2017.balance,0),2) as b2017, FORMAT(IFNULL(t2018.balance,0),2) as b2018, 
    FORMAT(IFNULL(t2019.balance,0),2) as b2019, FORMAT(IFNULL(t2020.balance,0),2) as b2020, FORMAT(IFNULL(t2026.balance,0),2) as b2026,
	FORMAT(IFNULL((t2016.balance - t2015.balance)/t2015.balance,0),2) as r15to16,
	FORMAT(IFNULL((t2017.balance - t2016.balance)/t2016.balance,0),2) as r16to17,
	FORMAT(IFNULL((t2018.balance - t2017.balance)/t2017.balance,0),2) as r17to18,
	FORMAT(IFNULL((t2019.balance - t2018.balance)/t2018.balance,0),2) as r18to19,
	FORMAT(IFNULL((t2020.balance - t2019.balance)/t2019.balance,0),2) as r19to20,
	FORMAT(IFNULL((t2026.balance - t2020.balance)/t2020.balance,0),2) as r20to26
-- to be able to compare all categories, we need to add the calculated sections to the table
FROM (	SELECT statement_section_order, CONCAT("  " , statement_section) as statement_section
		FROM statement_section
		WHERE is_balance_sheet_section = 0
			AND company_id = 1
		UNION
			SELECT 9.5 , 'GROSS PROFIT'
		UNION
			SELECT 11.5, 'PROFIT BEFORE TAXES'
		UNION
			SELECT 13.5, 'NET PROFIT') as statements
-- LEFT JOINING each year to the statement sections
LEFT JOIN (
SELECT year, totTable.category, totTable.balance 
FROM (
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 9.5 , 'GROSS PROFIT', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9)
	AND is_balance_sheet_section = 0
GROUP BY company_id, year

UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (10,11)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 11.5 , 'PROFIT BEFORE TAXES', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9,10,11)
	AND is_balance_sheet_section = 0
GROUP BY company_id, year

UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (12,13)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 13.5 , 'NET PROFIT', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE is_balance_sheet_section = 0
GROUP BY company_id, year) 
as totTable
	WHERE year = 2015
	AND company_id = 1
ORDER BY year, statement_section_order) as t2015
ON statement_section = t2015.category
LEFT JOIN (
SELECT year, totTable.category, totTable.balance 
FROM (
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 9.5 , 'GROSS PROFIT', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9)
	AND is_balance_sheet_section = 0
GROUP BY company_id, year

UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (10,11)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 11.5 , 'PROFIT BEFORE TAXES', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9,10,11)
	AND is_balance_sheet_section = 0
GROUP BY company_id, year

UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (12,13)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 13.5 , 'NET PROFIT', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE is_balance_sheet_section = 0
GROUP BY company_id, year) 
as totTable
	WHERE year = 2016
	AND company_id = 1
ORDER BY year, statement_section_order) as t2016
ON statement_section = t2016.category
LEFT JOIN (
SELECT year, totTable.category, totTable.balance 
FROM (
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 9.5 , 'GROSS PROFIT', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9)
	AND is_balance_sheet_section = 0
GROUP BY company_id, year

UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (10,11)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 11.5 , 'PROFIT BEFORE TAXES', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9,10,11)
	AND is_balance_sheet_section = 0
GROUP BY company_id, year

UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (12,13)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 13.5 , 'NET PROFIT', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE is_balance_sheet_section = 0
GROUP BY company_id, year) 
as totTable
	WHERE year = 2017
	AND company_id = 1
ORDER BY year, statement_section_order) as t2017
ON statement_section = t2017.category
LEFT JOIN (
SELECT year, totTable.category, totTable.balance 
FROM (
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 9.5 , 'GROSS PROFIT', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9)
	AND is_balance_sheet_section = 0
GROUP BY company_id, year

UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (10,11)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 11.5 , 'PROFIT BEFORE TAXES', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9,10,11)
	AND is_balance_sheet_section = 0
GROUP BY company_id, year

UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (12,13)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 13.5 , 'NET PROFIT', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE is_balance_sheet_section = 0
GROUP BY company_id, year) 
as totTable
	WHERE year = 2018
	AND company_id = 1
ORDER BY year, statement_section_order) as t2018
ON statement_section = t2018.category
LEFT JOIN (
SELECT year, totTable.category, totTable.balance 
FROM (
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 9.5 , 'GROSS PROFIT', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9)
	AND is_balance_sheet_section = 0
GROUP BY company_id, year

UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (10,11)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 11.5 , 'PROFIT BEFORE TAXES', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9,10,11)
	AND is_balance_sheet_section = 0
GROUP BY company_id, year

UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (12,13)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 13.5 , 'NET PROFIT', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE is_balance_sheet_section = 0
GROUP BY company_id, year) 
as totTable
	WHERE year = 2019
	AND company_id = 1
ORDER BY year, statement_section_order) as t2019
ON statement_section = t2019.category
LEFT JOIN (
SELECT year, totTable.category, totTable.balance 
FROM (
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 9.5 , 'GROSS PROFIT', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9)
	AND is_balance_sheet_section = 0
GROUP BY company_id, year

UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (10,11)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 11.5 , 'PROFIT BEFORE TAXES', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9,10,11)
	AND is_balance_sheet_section = 0
GROUP BY company_id, year

UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (12,13)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 13.5 , 'NET PROFIT', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE is_balance_sheet_section = 0
GROUP BY company_id, year) 
as totTable
	WHERE year = 2020
	AND company_id = 1
ORDER BY year, statement_section_order) as t2020
ON statement_section = t2020.category
LEFT JOIN (
SELECT year, totTable.category, totTable.balance 
FROM (
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 9.5 , 'GROSS PROFIT', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9)
	AND is_balance_sheet_section = 0
GROUP BY company_id, year

UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (10,11)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 11.5 , 'PROFIT BEFORE TAXES', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3,4,5,6,7,8,9,10,11)
	AND is_balance_sheet_section = 0
GROUP BY company_id, year

UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (12,13)
	AND is_balance_sheet_section = 0

UNION ALL

SELECT company_id, year, 13.5 , 'NET PROFIT', sum(balance)
FROM H_Accounting.mzurn_tmp
WHERE is_balance_sheet_section = 0
GROUP BY company_id, year) 
as totTable
	WHERE year = 2026
	AND company_id = 1
ORDER BY year, statement_section_order) as t2026
ON statement_section = t2026.category
ORDER BY statement_section_order;

/*
-- ---------------------------------------------------------------------------- --
-- Show the % change vs. the previous year for every major line item on the B/S --
-- ---------------------------------------------------------------------------- --
*/
-- SELECT all balances and calculate their ratios in comparison to the previous year
-- Starting off with all sections and left joining each year to it, to have a complete table.
-- The calculation is the same as above for the Profit and Loss, but we removed the comments to make the code shorter, all comments are above

SELECT statement_section as 'Balance Sheet', FORMAT(IFNULL(t2015.balance,0),2) as b2015, FORMAT(IFNULL(t2016.balance,0),2) as b2016, 
	FORMAT(IFNULL(t2017.balance,0),2) as b2017, FORMAT(IFNULL(t2018.balance,0),2) as b2018, 
    FORMAT(IFNULL(t2019.balance,0),2) as b2019, FORMAT(IFNULL(t2020.balance,0),2) as b2020, FORMAT(IFNULL(t2026.balance,0),2) as b2026,
	FORMAT(IFNULL((t2016.balance - t2015.balance)/t2015.balance,0),2) as r15to16,
	FORMAT(IFNULL((t2017.balance - t2016.balance)/t2016.balance,0),2) as r16to17,
	FORMAT(IFNULL((t2018.balance - t2017.balance)/t2017.balance,0),2) as r17to18,
	FORMAT(IFNULL((t2019.balance - t2018.balance)/t2018.balance,0),2) as r18to19,
	FORMAT(IFNULL((t2020.balance - t2019.balance)/t2019.balance,0),2) as r19to20,
	FORMAT(IFNULL((t2026.balance - t2020.balance)/t2020.balance,0),2) as r20to26
-- to be able to compare all categories, we need to add the calculated sections to the table
FROM (	SELECT statement_section_order, CONCAT("  " , statement_section) as statement_section
		FROM statement_section
		WHERE is_balance_sheet_section != 0
			AND company_id = 1
		UNION 
			SELECT 0.1, 'ASSETS'
        UNION
			SELECT 3.6, 'TOTAL ASSETS'
		UNION
			SELECT 3.65, ''
		UNION
			SELECT 3.7, 'LIABILITIES AND SHAREHOLDERS EQUITY'
		UNION
			SELECT 6.5, 'TOTAL LIABILITIES'
		UNION
			SELECT 6.6, 'SHAREHOLDERS EQUITY'
		UNION
			SELECT 7.5, 'TOTAL LIABILITIES AND SHAREHOLDERS EQUITY'
    
    ) as statements
-- LEFT JOINING each year to the statement sections
LEFT JOIN (SELECT totTable.statement_section_order, totTable.category, totTable.balance 
FROM (
SELECT -1000 as company_id, 0.0 as year, 0.0 as statement_section_order, '' as Category, '' as balance
UNION ALL
SELECT -1000, 0, 0.1, 'ASSETS', ''
UNION ALL
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3)
	AND is_balance_sheet_section = 1
UNION ALL

SELECT company_id, year, 3.6, 'TOTAL ASSETS' as category, sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year

UNION ALL

SELECT -1000, 0, 3.65, '', ''
UNION ALL

SELECT -1000, 0, 3.7, 'LIABILITIES AND SHAREHOLDERS EQUITY', ''
UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, -1*balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6)
	AND is_balance_sheet_section = 1
    
UNION ALL

SELECT company_id, year, 6.5, 'TOTAL LIABILITIES' as category, -1*sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year

UNION ALL
SELECT -1000, 0, 6.6, 'SHAREHOLDERS EQUITY', ''
UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, -1*balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (7)
	AND is_balance_sheet_section = 1
    
UNION ALL

SELECT company_id, year, 7.5, 'TOTAL LIABILITIES AND SHAREHOLDERS EQUITY' as category, -1*sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6,7)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year
) as totTable
WHERE company_id IN (1,-1000)
	AND year IN (2015, 0)
ORDER BY statement_section_order) as t2015
ON statements.statement_section_order = t2015.statement_section_order
LEFT JOIN (SELECT totTable.statement_section_order, totTable.category, totTable.balance 
FROM (
SELECT -1000 as company_id, 0.0 as year, 0.0 as statement_section_order, '' as Category, '' as balance
UNION ALL
SELECT -1000, 0, 0.1, 'ASSETS', ''
UNION ALL
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3)
	AND is_balance_sheet_section = 1
UNION ALL

SELECT company_id, year, 3.6, 'TOTAL ASSETS' as category, sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year

UNION ALL

SELECT -1000, 0, 3.65, '', ''
UNION ALL

SELECT -1000, 0, 3.7, 'LIABILITIES AND SHAREHOLDERS EQUITY', ''
UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, -1*balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6)
	AND is_balance_sheet_section = 1
    
UNION ALL

SELECT company_id, year, 6.5, 'TOTAL LIABILITIES' as category, -1*sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year

UNION ALL
SELECT -1000, 0, 6.6, 'SHAREHOLDERS EQUITY', ''
UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, -1*balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (7)
	AND is_balance_sheet_section = 1
    
UNION ALL

SELECT company_id, year, 7.5, 'TOTAL LIABILITIES AND SHAREHOLDERS EQUITY' as category, -1*sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6,7)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year
) as totTable
WHERE company_id IN (1,-1000)
	AND year IN (2016, 0)
ORDER BY statement_section_order) as t2016
ON statements.statement_section_order = t2016.statement_section_order
LEFT JOIN (SELECT totTable.statement_section_order, totTable.category, totTable.balance 
FROM (
SELECT -1000 as company_id, 0.0 as year, 0.0 as statement_section_order, '' as Category, '' as balance
UNION ALL
SELECT -1000, 0, 0.1, 'ASSETS', ''
UNION ALL
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3)
	AND is_balance_sheet_section = 1
UNION ALL

SELECT company_id, year, 3.6, 'TOTAL ASSETS' as category, sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year

UNION ALL

SELECT -1000, 0, 3.65, '', ''
UNION ALL

SELECT -1000, 0, 3.7, 'LIABILITIES AND SHAREHOLDERS EQUITY', ''
UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, -1*balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6)
	AND is_balance_sheet_section = 1
    
UNION ALL

SELECT company_id, year, 6.5, 'TOTAL LIABILITIES' as category, -1*sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year

UNION ALL
SELECT -1000, 0, 6.6, 'SHAREHOLDERS EQUITY', ''
UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, -1*balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (7)
	AND is_balance_sheet_section = 1
    
UNION ALL

SELECT company_id, year, 7.5, 'TOTAL LIABILITIES AND SHAREHOLDERS EQUITY' as category, -1*sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6,7)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year
) as totTable
WHERE company_id IN (1,-1000)
	AND year IN (2017, 0)
ORDER BY statement_section_order) as t2017
ON statements.statement_section_order = t2017.statement_section_order
LEFT JOIN (SELECT totTable.statement_section_order, totTable.category, totTable.balance 
FROM (
SELECT -1000 as company_id, 0.0 as year, 0.0 as statement_section_order, '' as Category, '' as balance
UNION ALL
SELECT -1000, 0, 0.1, 'ASSETS', ''
UNION ALL
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3)
	AND is_balance_sheet_section = 1
UNION ALL

SELECT company_id, year, 3.6, 'TOTAL ASSETS' as category, sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year

UNION ALL

SELECT -1000, 0, 3.65, '', ''
UNION ALL

SELECT -1000, 0, 3.7, 'LIABILITIES AND SHAREHOLDERS EQUITY', ''
UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, -1*balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6)
	AND is_balance_sheet_section = 1
    
UNION ALL

SELECT company_id, year, 6.5, 'TOTAL LIABILITIES' as category, -1*sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year

UNION ALL
SELECT -1000, 0, 6.6, 'SHAREHOLDERS EQUITY', ''
UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, -1*balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (7)
	AND is_balance_sheet_section = 1
    
UNION ALL

SELECT company_id, year, 7.5, 'TOTAL LIABILITIES AND SHAREHOLDERS EQUITY' as category, -1*sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6,7)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year
) as totTable
WHERE company_id IN (1,-1000)
	AND year IN (2018, 0)
ORDER BY statement_section_order) as t2018
ON statements.statement_section_order = t2018.statement_section_order
LEFT JOIN (SELECT totTable.statement_section_order, totTable.category, totTable.balance 
FROM (
SELECT -1000 as company_id, 0.0 as year, 0.0 as statement_section_order, '' as Category, '' as balance
UNION ALL
SELECT -1000, 0, 0.1, 'ASSETS', ''
UNION ALL
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3)
	AND is_balance_sheet_section = 1
UNION ALL

SELECT company_id, year, 3.6, 'TOTAL ASSETS' as category, sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year

UNION ALL

SELECT -1000, 0, 3.65, '', ''
UNION ALL

SELECT -1000, 0, 3.7, 'LIABILITIES AND SHAREHOLDERS EQUITY', ''
UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, -1*balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6)
	AND is_balance_sheet_section = 1
    
UNION ALL

SELECT company_id, year, 6.5, 'TOTAL LIABILITIES' as category, -1*sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year

UNION ALL
SELECT -1000, 0, 6.6, 'SHAREHOLDERS EQUITY', ''
UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, -1*balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (7)
	AND is_balance_sheet_section = 1
    
UNION ALL

SELECT company_id, year, 7.5, 'TOTAL LIABILITIES AND SHAREHOLDERS EQUITY' as category, -1*sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6,7)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year
) as totTable
WHERE company_id IN (1,-1000)
	AND year IN (2019, 0)
ORDER BY statement_section_order) as t2019
ON statements.statement_section_order = t2019.statement_section_order
LEFT JOIN (SELECT totTable.statement_section_order, totTable.category, totTable.balance 
FROM (
SELECT -1000 as company_id, 0.0 as year, 0.0 as statement_section_order, '' as Category, '' as balance
UNION ALL
SELECT -1000, 0, 0.1, 'ASSETS', ''
UNION ALL
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3)
	AND is_balance_sheet_section = 1
UNION ALL

SELECT company_id, year, 3.6, 'TOTAL ASSETS' as category, sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year

UNION ALL

SELECT -1000, 0, 3.65, '', ''
UNION ALL

SELECT -1000, 0, 3.7, 'LIABILITIES AND SHAREHOLDERS EQUITY', ''
UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, -1*balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6)
	AND is_balance_sheet_section = 1
    
UNION ALL

SELECT company_id, year, 6.5, 'TOTAL LIABILITIES' as category, -1*sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year

UNION ALL
SELECT -1000, 0, 6.6, 'SHAREHOLDERS EQUITY', ''
UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, -1*balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (7)
	AND is_balance_sheet_section = 1
    
UNION ALL

SELECT company_id, year, 7.5, 'TOTAL LIABILITIES AND SHAREHOLDERS EQUITY' as category, -1*sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6,7)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year
) as totTable
WHERE company_id IN (1,-1000)
	AND year IN (2020, 0)
ORDER BY statement_section_order) as t2020
ON statements.statement_section_order = t2020.statement_section_order
LEFT JOIN (SELECT totTable.statement_section_order, totTable.category, totTable.balance 
FROM (
SELECT -1000 as company_id, 0.0 as year, 0.0 as statement_section_order, '' as Category, '' as balance
UNION ALL
SELECT -1000, 0, 0.1, 'ASSETS', ''
UNION ALL
SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3)
	AND is_balance_sheet_section = 1
UNION ALL

SELECT company_id, year, 3.6, 'TOTAL ASSETS' as category, sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (1,2,3)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year

UNION ALL

SELECT -1000, 0, 3.65, '', ''
UNION ALL

SELECT -1000, 0, 3.7, 'LIABILITIES AND SHAREHOLDERS EQUITY', ''
UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, -1*balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6)
	AND is_balance_sheet_section = 1
    
UNION ALL

SELECT company_id, year, 6.5, 'TOTAL LIABILITIES' as category, -1*sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year

UNION ALL
SELECT -1000, 0, 6.6, 'SHAREHOLDERS EQUITY', ''
UNION ALL

SELECT company_id, year, statement_section_order, CONCAT("  " , statement_section) as category, -1*balance as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (7)
	AND is_balance_sheet_section = 1
    
UNION ALL

SELECT company_id, year, 7.5, 'TOTAL LIABILITIES AND SHAREHOLDERS EQUITY' as category, -1*sum(balance) as balance 
FROM H_Accounting.mzurn_tmp
WHERE statement_section_order IN (4,5,6,7)
	AND is_balance_sheet_section = 1
GROUP BY company_id, year
) as totTable
WHERE company_id IN (1,-1000)
	AND year IN (2026, 0)
ORDER BY statement_section_order) as t2026
ON statements.statement_section_order = t2026.statement_section_order
ORDER BY statements.statement_section_order;



