--1. Calulate Quantity of items, Sales value & Order quantity by each Subcategory in the last 12 months
SELECT DISTINCT
       FORMAT_DATETIME("%b %Y", a.ModifiedDate) AS Period
      ,c.Name AS Subcategory
      ,SUM(a.OrderQty) AS ItemCount
      ,SUM(a.LineTotal) AS SalesValue
      ,COUNT(DISTINCT a.SalesOrderID) AS OrderCount
FROM `adventureworks2019.Sales.SalesOrderDetail` a
LEFT JOIN `adventureworks2019.Production.Product` b ON a.ProductID = b.ProductID
LEFT JOIN `adventureworks2019.Production.ProductSubcategory` c ON CAST(b.ProductSubcategoryID AS int) = c.ProductSubcategoryID
WHERE DATE(a.ModifiedDate) BETWEEN (DATE_SUB(DATE(a.ModifiedDate), INTERVAL 12 month)) AND '2014-06-30'
GROUP BY 1, 2
ORDER BY Period DESC, Subcategory ASC;

--2. Calculate the % YoY growth rate by Subcategory & get the top 3 Subcategory with highest growth rate
WITH Order_Table AS (
      SELECT c.Name AS Name
            ,EXTRACT(YEAR FROM DATETIME(a.ModifiedDate)) AS Year
            ,SUM(a.OrderQty) AS Qty_item
      FROM `adventureworks2019.Sales.SalesOrderDetail` a
      LEFT JOIN `adventureworks2019.Production.Product` b ON a.ProductID = b.ProductID
      LEFT JOIN `adventureworks2019.Production.ProductSubcategory` c ON cast(b.ProductSubcategoryID AS int) = c.ProductSubcategoryID
      GROUP BY Year, Name)
,
     Lag_table AS (
      SELECT *
            ,LAG(Qty_item, 1) OVER(PARTITION BY Name ORDER BY Year) AS Prv_qty
      FROM Order_Table)
,    Diff_table AS (
      SELECT Name
      ,Qty_item
      ,Prv_qty
      ,ROUND((Qty_item-Prv_qty)/Prv_qty,2) AS Qty_diff
      FROM Lag_table)
SELECT Name
      ,Qty_item
      ,Prv_qty
      ,Qty_diff 
      ,DENSE_RANK()OVER(ORDER BY Qty_diff DESC) Rank 
FROM Diff_table;

--3. Rank top 3 TeritoryID with greatest Order quantity per year (not skip the rank number for TerritoryID with the same quantity)
WITH Territory_table AS
      (SELECT EXTRACT(YEAR FROM DATETIME(a.ModifiedDate)) AS Year
             ,TerritoryID
             ,SUM(a.OrderQty) AS OrderQty
      FROM `adventureworks2019.Sales.SalesOrderDetail` a
      LEFT JOIN `adventureworks2019.Sales.SalesOrderHeader` b ON a.SalesOrderID = b.SalesOrderID
      GROUP BY Year, TerritoryID)
,
      Rank_table AS
      (SELECT *
             ,DENSE_RANK()OVER(PARTITION BY Year ORDER BY OrderQty DESC) AS Rank
      FROM Territory_table)
SELECT * FROM Rank_table WHERE Rank <= 3    
ORDER BY Year DESC;

--4. Calculate the Total Discount Cost that is Seasonal Discount for each SubCategory
SELECT FORMAT_TIMESTAMP("%Y", ModifiedDate) AS Year
      ,Name
      ,SUM(disc_cost) as Total_cost
FROM (
      SELECT DISTINCT a.*
            ,c.Name
            ,d.DiscountPct
            ,d.Type
            ,a.OrderQty * d.DiscountPct * UnitPrice AS Disc_cost 
      FROM `adventureworks2019.Sales.SalesOrderDetail` a
      LEFT JOIN `adventureworks2019.Production.Product` b ON a.ProductID = b.ProductID
      LEFT JOIN `adventureworks2019.Production.ProductSubcategory` c on CAST (b.ProductSubcategoryID AS int) = c.ProductSubcategoryID
      LEFT JOIN `adventureworks2019.Sales.SpecialOffer` d ON a.SpecialOfferID = d.SpecialOfferID
      WHERE LOWER(d.Type) LIKE '%seasonal discount%' 
)
GROUP BY 1,2 ;

--5. Calculate the Retention rate of Customer in 2014 with status 'Successfully Shipped'
WITH 
info AS (
  SELECT  
      EXTRACT(month FROM ModifiedDate) AS month_no
     ,EXTRACT(year FROM ModifiedDate) AS year_no
     ,CustomerID
     ,COUNT(DISTINCT SalesOrderID) AS order_cnt
  FROM `adventureworks2019.Sales.SalesOrderHeader`
  WHERE FORMAT_TIMESTAMP("%Y", ModifiedDate) = '2014' AND Status = 5
  GROUP BY 1,2,3
  ORDER BY 3,1 
),
row_num AS (
  SELECT *
      , ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY month_no) AS row_numb
  FROM info 
), 
first_order AS (
  SELECT *
  FROM row_num
  WHERE row_numb = 1
), 
month_gap AS (
  SELECT 
      a.CustomerID
     ,b.month_no AS month_join
     ,a.month_no AS month_order
     ,a.order_cnt
     ,CONCAT('M - ',a.month_no - b.month_no) AS month_diff
  FROM info a 
  LEFT JOIN first_order b ON a.CustomerID = b.CustomerID
  ORDER BY 1,3
)
SELECT month_join
      ,month_diff 
      ,COUNT(DISTINCT CustomerID) AS customer_cnt
FROM month_gap
GROUP BY 1,2
ORDER BY 1,2;

--6. Show the trend of Stock level and %MoM difference of all products in 2011 (If %growth rate is null => replace with 0)
WITH Stk_table AS (
      SELECT Name AS ProductName
            ,EXTRACT(MONTH FROM DATETIME(b.ModifiedDate)) AS Month
            ,EXTRACT(YEAR FROM DATETIME(b.ModifiedDate)) AS Year
            ,SUM(StockedQty) AS StockQty
      FROM `adventureworks2019.Production.Product` a
      LEFT JOIN `adventureworks2019.Production.WorkOrder` b ON a.ProductID = b.ProductID
      GROUP BY Year, ProductName, Month
      ORDER BY Year ASC)
,
    Lag_table AS (
      SELECT *
            ,LAG(StockQty, 1) OVER(PARTITION BY ProductName ORDER BY Month) AS StockPrv
      FROM Stk_table
      WHERE Year=2011)
,
    Trend_table AS (
      SELECT *
            ,ROUND(((StockQty-StockPrv)/StockPrv)*100,1) AS StockDiff
      FROM Lag_table)
SELECT ProductName
      ,Month
      ,Year
      ,StockQty
      ,StockPrv
      ,IFNULL(StockDiff, 0) AS StockDiff
FROM Trend_table
ORDER BY ProductName ASC, Month DESC;

--7. Calculate the ratio of Stock/ Sales in 2011 by product name & by month 
WITH Sales_table AS (
      SELECT EXTRACT(MONTH FROM DATETIME(a.ModifiedDate)) AS Month
            ,EXTRACT(YEAR FROM DATETIME(a.ModifiedDate)) AS Year
            ,a.ProductID
            ,Name AS ProductName
            ,SUM(OrderQty) AS Sales
      FROM `adventureworks2019.Sales.SalesOrderDetail` a
      LEFT JOIN `adventureworks2019.Production.Product` b ON a.ProductID = b.ProductID
      WHERE EXTRACT(YEAR FROM DATETIME(a.ModifiedDate))=2011
      GROUP BY Year, ProductName, Month, ProductID)
,  
     Stock_table AS (
      SELECT ProductID
            ,EXTRACT(MONTH FROM DATETIME(ModifiedDate)) AS Month
            ,EXTRACT(YEAR FROM DATETIME(ModifiedDate)) AS Year
            ,SUM(StockedQty) AS Stock
      FROM `adventureworks2019.Production.WorkOrder`
      WHERE EXTRACT(YEAR FROM DATETIME(ModifiedDate))=2011
      GROUP BY ProductID, Year, Month)
SELECT a.Month
      ,a.Year
      ,a.ProductID
      ,ProductName
      ,Sales
      ,COALESCE(b.Stock, 0) AS Stock
      ,ROUND(COALESCE(b.Stock,0)/Sales, 2) AS Ratio    
FROM Sales_table a
LEFT JOIN Stock_table b ON a.ProductID = b.ProductID
ORDER BY Month DESC, Ratio DESC;

--8. Get the number of order & value with Pending status in 2014
SELECT EXTRACT(YEAR FROM DATETIME(ModifiedDate)) AS Year
      ,Status
      ,COUNT (DISTINCT PurchaseOrderID) AS OrderCount
      ,SUM(TotalDue) AS Value
FROM `adventureworks2019.Purchasing.PurchaseOrderHeader`
WHERE Status=1 AND EXTRACT(YEAR FROM DATETIME(ModifiedDate))=2014
GROUP BY Year, Status