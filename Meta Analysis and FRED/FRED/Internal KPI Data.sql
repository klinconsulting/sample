/* Write your queries in this editor and hit Run button or Shift + Return to execute */
/*   This code pulls retail related metrics at the merchant brand level for the most recent entire 2 years*/                     
                     
                     
/* A distinct list of ASINs and categories to define the scope of a story*/                     
                     
-- 6 Mins                     
CREATE TEMP TABLE TMP_ASIN_List                     
DISTKEY(asin)                     
SORTKEY(asin)                     
AS                     
SELECT                     
     dma.ASIN                     
--    ,dma.item_name                     
    ,dma.gl_product_group       
FROM                     
 BOOKER.D_MP_ASINS dma                    
WHERE 1=1                                      
       AND dma.MARKETPLACE_ID = {MARKETPLACE_ID}                       
       AND dma.gl_product_group = {gl_product_group}   --- update your GL code.                     
               
              
;                     
                     
                     
/*sales by asin by day to join later */                     
-- 25 Mins                     
CREATE TEMP TABLE orders_yr1 -- 1 minutes                     
DISTKEY(asin)                     
SORTKEY(asin)                     
AS                     
SELECT                     
    ucoi.order_day                   
  , ucoi.asin                   
  ---      , ucoi.merchant_customer_id  --avoid double counting if the same ASIN belongs to different merchants                   
  ----      , ucoi.IS_RETAIL_ORDER_ITEM          /*ICS tries to include both vendor and seller that both can do advertising*/                     
  , SUM(NVL(ucoi.QUANTITY, 0)) AS asin_units                   
  , SUM(NVL((ucoi.OUR_PRICE * ucoi.QUANTITY), 0)) AS asin_sales                   
                            
                     
 FROM                    
  booker.d_unified_customer_order_items_vw ucoi                   
 WHERE 1=1                    
     AND ucoi.OUR_PRICE > 0                   
  AND ucoi.IS_FREE_REPLACEMENT = 'N'                   
  AND ucoi.ORDER_ITEM_LEVEL_CONDITION = 4                   
  AND ( ucoi.order_day between to_date({start_date}, 'YYYYMMDD') and to_date ({end_date}, 'YYYYMMDD')                   
 )                   
  /*UPDATE DATE RANGE */                   
  and marketplace_id = 1                     
  and asin in (select asin from TMP_ASIN_List group by asin)                   
 GROUP BY                    
    ucoi.order_day                   
  , ucoi.asin                   
  ---      , ucoi.merchant_customer_id                     
  ---     , ucoi.IS_RETAIL_ORDER_ITEM       /*ICS tries to include both vendor and seller*/                     
;                     
                     

create temp table asin_brand
distkey(ASIN)
sortkey (ASIN)
as

   select 
   ASIN
  ,brand_id
  ,brand_name
  from identity_hub.dim_asin_brand_v2
  where 1=1
  and marketplace_id= 1  -- adjust your marketplace
  and asin in (select asin from TMP_ASIN_List)
  
  group by 1,2,3;


/*adding brandreivews per ASIN*/                     
                     
drop table if exists final_sales;
CREATE TEMP TABLE final_sales
as
SELECT                   
     ab.brand_id                    
 ,ab.brand_name -- BRAND LEVEL
,order_day           
 ,SUM (am8.asin_units) as brandunits                   
 ,SUM (am8.asin_sales) as brandsales                    
                   
                     
FROM     orders_yr1 am8                    
 left join TMP_ASIN_List A  
      on am8.ASIN=A.asin 
 Left join asin_brand ab
      on am8.ASIN=ab.ASIN

                    
where 1=1                    
                     
GROUP BY 1,2,3; 

/* This query asin level impressions for AMG products */

/* scope the asins for analysis by retail categories */
DROP TABLE IF EXISTS ASIN_scope;
CREATE TEMP TABLE asin_scope                                
DISTKEY (asin)                                            
SORTKEY (asin)                                            
AS
SELECT
    asins.asin
--  , dgpg.gl_PRODUCT_GROUP_ID
--  , dac.product_category
--  , das.product_subcategory

from  adw_metrics_glue.dim_asins asins
  left JOIN adw_metrics_glue.dim_gl_product_groups dgpg ON (asins.DIM_GL_PRODUCT_GROUP_ID = dgpg.DIM_GL_PRODUCT_GROUP_ID)  --- this is redundant but not wrong as fdac table already has GL id, this is also the GL code, not just match key. 
  LEFT JOIN adw_metrics_glue.DIM_ASIN_CATS dac ON (asins.dim_asin_cat_key = dac.dim_asin_cat_key)
  LEFT JOIN adw_metrics_glue.DIM_ASIN_SUBCATS das ON (asins.dim_asin_subcat_key = das.dim_asin_subcat_key)
where 1=1
    AND dgpg.gl_product_group_id = {gl_product_group}    --- adjust your GL code. It's the retail GL code, not the dim_gl_product_group_id

  
    and asins.marketplace_id=1
group by 1;


/* pull ASIN level traffic and conversion from ICSstaging tables */
drop table if exists asin_perf;
create TEMP Table asin_perf
Distkey (ASIN)
sortkey (ASIN)
AS
Select 
  asin
, platform
, device_type
, ad_product_type
,activity_date
, sum(impressions) as asin_impressions
, sum(detail_page_views) as dpv
-- , sum(detail_page_views) as asin_adattributed_DPVs
-- , SUM (attributed_gms_lc) as asin_adattributed_sales
-- , SUM (attributed_units) as asin_adattributed_units
-- , sum (ad_revenue_lc) as asin_adspend

from ics_staging.fact_amg_asin_performance_prod --- change ics_staging tables to change ad products

where 1=1
and marketplace_id=1
and activity_date between to_date({start_date}, 'YYYYMMDD') and to_date ({end_date}, 'YYYYMMDD') -- adjust based on your study period 
group by 1,2,3,4,5;

/* Aggregate ASIN level performance to brand level */
drop table if exists FINAL_AMG;
create TEMP table FINAL_AMG
as
select 
  brand_id
, brand_name
, activity_date
, sum(case when UPPER(device_type) LIKE '%VIDEO%' and UPPER (ad_product_type) not like '%OTT%' THEN asin_impressions
         
else '0' end) AS Video_impressions   --- sum impressions delivered by video (no SBV) product at a brand level 

, sum(case when UPPER(device_type) LIKE '%FIRE%TV%'  THEN asin_impressions
else '0' end) AS Firetv_impressions   --- sum impressions delivered by Fire TV at a brand level 


, sum(case when UPPER(platform) like '%DISPLAY%' and upper (device_type) not like '%VIDEO%' THEN asin_impressions
else '0' end) AS Display_impressions     --- sum impressions delivered by Display product family without DSP at a brand level

, sum(case when UPPER(platform) like '%DSP%' THEN asin_impressions
else '0' end) AS DSP_impressions     --- sum impressions delivered by DSP Display at a brand level, no audio or video is included 

, sum(case when UPPER(platform) LIKE '%AUDIO%'  THEN asin_impressions
else '0' end) AS Audio_impressions    --- sum impressions delivered by audio product family at a brand level

, sum(case when UPPER(device_type) LIKE '%OTT%'  THEN asin_impressions
else '0' end) AS OTT_impressions     --- sum impressions delivered by OTT product family at a brand level 

,sum(dpv) dpv

from asin_brand as ab
join asin_perf as ap
on ab.asin=ap.asin
where 1=1
group by 1,2,3; 

select i.brand_name
        , i.activity_date
        ,sum(Video_impressions) Video_impressions
        ,sum(Firetv_impressions) Firetv_impressions
        ,sum(Display_impressions) Display_impressions
        ,sum(DSP_impressions) DSP_impressions
        ,sum(Audio_impressions) Audio_impressions
        ,sum(OTT_impressions) OTT_impressions
        ,sum(dpv) dpv
        ,sum(brandunits) brandunits
        ,sum(brandsales) brandsales
from FINAL_AMG i 
right join final_sales c 
on i.brand_id = c.brand_id
and i.brand_name = c.brand_name
and i.activity_date  = c.order_day
where 1=1
group by 1,2