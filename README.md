# Northwind sales analysis

Four PostgreSQL queries explore sales in the Northwind sample database. Revenue is calculated from order lines as unit price times quantity, after discount.

The analysis covers monthly revenue and growth, cumulative sales by category in 1997, employee sales ranking and revenue share, and order history for the five customers with the highest sales. The queries use CTEs to aggregate the data before applying window functions such as `LAG`, `RANK` and `SUM OVER`.

## Run locally

Create a database and load [the PostgreSQL version of Northwind](https://github.com/pthom/northwind_psql/blob/master/northwind.sql). With that file saved as `northwind.sql` in your current directory, run the following.

```sh
createdb northwind_demo
psql -X -v ON_ERROR_STOP=1 -d northwind_demo -f northwind.sql
git clone https://github.com/Eduardo-Torres-Data/northwind-sales-analysis.git
cd northwind-sales-analysis
psql -X -v ON_ERROR_STOP=1 -d northwind_demo -f queries/01_northwind_sales_analysis.sql
```

## Sample results

- [Monthly sales and month-over-month growth](images/Result1.png)
- [Cumulative sales by category in 1997](images/Resul2.png)
- [Employee sales ranking and revenue share](images/Result3.png)
- [Order history for the top five customers](images/Resul4.png)
