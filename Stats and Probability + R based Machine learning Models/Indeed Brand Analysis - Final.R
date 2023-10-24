library(ggplot2)
library(tidyverse)
library(stats)
library(dplyr)
library(factoextra)
library(lubridate)
library(RColorBrewer)
library(cluster)
library(stringr)
library(caret)
library(ranger)
library(rattle)
library(rpart)
library(glmnet)
library(tidyr)
library(broom)

df <- read.csv("Data Source.csv")
# df_md <- read.csv("MatchTable-VIEW_Daypart_Expande.csv")
# df_md <- df_md %>% filter(Plan == "Brand")
# 
df <- df %>% filter(LOB == "Brand") %>%
  select( Conversion.Type,Network,Network.2,Show,
          Show.Genre,Show.Subgenre, Duration,Impressions, Conversion.Events)

# Conversion Events
df_summary1 <- df %>% group_by(Network,Network.2, Show, Conversion.Type) %>% 
  summarize(total_conversion = sum(Conversion.Events, na.rm = TRUE)) %>% 
  pivot_wider(names_from = "Conversion.Type", values_from = "total_conversion")

colnames(df_summary1)[4:ncol(df_summary1)] <- gsub(" ","_", colnames(df_summary1)[4:ncol(df_summary1)])

# Impression and duration 15 seconds
df_summary2 <- df %>% group_by(Network,Network.2, Show, Show.Genre, Show.Subgenre, Duration) %>%
               summarize(total_imp = sum(Impressions, na.rm = TRUE),n=n()) 


demo_q <- read.csv("Demographic Data - ES.csv")
question_mapping <- read.csv("demographic questions mapping.csv")
category_mapping <- read.csv("Model Category.csv")
total_q <- read.csv("data_mapped_test.csv")

# Only select either job function or occupation category
#category_to_remove <- "Job Function/Area of Responsibility"
category_to_remove <- "Employment Status/Occupation - Respondent"

category_mapping <- category_mapping %>% filter(Model_Category !=category_to_remove)

question_mapping <- question_mapping %>% 
  filter(Category %in% category_mapping$Model_Category)

col_label <- colnames(demo_q)[2:ncol(demo_q)] %in% question_mapping$Attributes

demo_q <- demo_q[,c(TRUE, col_label)]
total_q_demo_label <- colnames(total_q[2:ncol(total_q)]) %in% question_mapping$Attributes
total_q_demo <- total_q[,c(TRUE,total_q_demo_label)]

compute_duration_perc <- function(x){
   
  # Proportion of 15 sec ads
  x_duration15 <- x %>% filter(Duration==15)
  x$duration15_percent <- ifelse(nrow(x_duration15)==0,0,x_duration15$n / sum(x$n))
  
  # Proportion of 30 sec ads
  x_duration30 <- x %>% filter(Duration==30)
  x$duration30_percent <- ifelse(nrow(x_duration30)==0,0,x_duration30$n / sum(x$n))
  
  # Proportion of 60 sec ads
  x_duration60 <- x %>% filter(Duration==60)
  x$duration60_percent <- ifelse(nrow(x_duration60)==0,0,x_duration15$n / sum(x$n))
  
  return (x)
}

df_summary2.1 <- df_summary2 %>% group_by(Network,Network.2, Show, Show.Genre, Show.Subgenre) %>%
                 group_split() %>% map_df(.,compute_duration_perc) %>% select(-n) 

# df_summary2 <- df %>% group_by(Network,Network.2, Show, Show.Genre, Show.Subgenre, Duration) %>%
#   summarize(total_imp = sum(Impressions, na.rm = TRUE), n=n())  %>%
#   mutate(duration_percent = n / sum(n)) %>% select(-n, -Duration) 

df_summary3 <- df_summary1 %>% inner_join(df_summary2.1, by=c("Network","Network.2","Show")) %>%
                mutate(Engagement_Score = (10*View_Job + 100*Job_Apply) / total_imp * 100) %>% 
                ungroup()

df_summary3 <- df_summary3 %>% na.omit(.) %>% 
  mutate_if(is.character, as.factor)

#df_summary3 <- df_summary3 %>% inner_join(demo_q, by="Network")

###### Box plot on Engagement Score and show large outliers

ggplot(df_summary3, aes(y=Engagement_Score)) + geom_boxplot() +
  theme_bw() + labs(title="Box Plot Of Engagement Score - Pre-tranformation", 
                    y="Engagement Score") +  
  theme(axis.title.x=element_blank(),
        axis.text.x=element_blank(),
        axis.ticks.x=element_blank())


# Due to large outlier, we need to do log-transformation on the response variable
df_summary3$Engagement_Score <- log(df_summary3$Engagement_Score)

ggplot(df_summary3, aes(y=Engagement_Score)) + geom_boxplot() +
  theme_bw() + labs(title="Box Plot Of Engagement Score - Post-tranformation", 
                    y="Engagement Score") +
  theme(axis.title.x=element_blank(),
        axis.text.x=element_blank(),
        axis.ticks.x=element_blank())

##### Cluster Analysis


data_cluster <- df_summary3 %>% select_if(is.numeric) %>% scale(.)
 

k_values <- seq(2:10)

set.seed(1234)
kmeans_mod_list <- map(k_values, function(x) kmeans(data_cluster,centers=x, nstart = 10, iter.max=100))
tot_withinss <- map_dbl(kmeans_mod_list, function(x) x$tot.withinss)

df_kmeans <- data.frame(k=k_values,total_within_ssq = tot_withinss)
ggplot(df_kmeans, aes(k, total_within_ssq)) + geom_line() +
  labs(x="Number of Cluster", y="Total Within Cluster Sum Of Square") +
  theme_bw() + scale_x_continuous(breaks=seq(1:10))

fviz_nbclust(data_cluster, kmeans, method = "silhouette")

opt_k <- 2
final_kmean_mod <- kmeans(data_cluster, centers=opt_k, nstart=10, iter.max = 100)

data_cluster_final <- df_summary3 %>%
  mutate(cluster=final_kmean_mod$cluster)



cluster_result1 <- data_cluster_final %>% group_by(cluster) %>% 
  summarize(Avg_Escore = mean(Engagement_Score),Avg_JobApply = mean(Job_Apply),
            Avg_ViewJob = mean(View_Job), Avg_TotalImp = mean(total_imp),
            Avg_Duration15 = mean(duration15_percent), Avg_Duration30 = mean(duration30_percent),
            Avg_Duration60 = mean(duration60_percent)) 

cluster_result2 <- data_cluster_final %>% count(cluster, Show.Genre, Show.Subgenre)

#row.names(data_cluster) <- data_merged$Network
fviz_cluster(final_kmean_mod, data = data_cluster)

######## More plot on the clusters

# By Genre
ggplot(cluster_result2, aes(x=Show.Genre, y=n, fill=Show.Genre)) +
  geom_bar(stat="identity") + facet_wrap(~cluster, scales = "free") +
  coord_flip() + labs(title="Number of Observtions by Genre and Cluster", 
                      y="Number of Observations", 
                      x="Show Genre", fill="Genre") + theme_bw() +
  theme(legend.position = "none")

# By Sub-Genre
ggplot(cluster_result2 %>% filter(cluster==1), aes(x=reorder(Show.Subgenre,n), y=n, fill=Show.Subgenre)) +
  geom_bar(stat="identity") +
  coord_flip() + labs(title="Cluster 1: Number of Observtions by Sub-Genre", 
                      y="Number of Observations", 
                      x="Show Genre", fill="Sub-Genre") + theme_bw() +
  theme(legend.position = "none") 

ggplot(cluster_result2 %>% filter(cluster==2), aes(x=reorder(Show.Subgenre,n), y=n, fill=Show.Subgenre)) +
  geom_bar(stat="identity") +
  coord_flip() + labs(title="Cluster 2: Number of Observtions by Sub-Genre", 
                      y="Number of Observations", 
                      x="Show Genre", fill="Sub-Genre") + theme_bw() +
  theme(legend.position = "none") 

# df_summary3 <- df_summary3 %>% mutate(cluster = final_kmean_mod$cluster) %>%
#   inner_join(demo_q, by="Network")

df_summary3 <- df_summary3 %>%
  inner_join(demo_q, by="Network")

df_summary4 <- df_summary3 %>% pivot_longer(-c(1:16), names_to = "Demo_Q", values_to = "Demo_Score")
df_summary4 <- df_summary4 %>% inner_join(question_mapping, by=c("Demo_Q"="Attributes"))

df_summary5 <- df_summary4 %>% group_by(Category, Engagement_Score) %>% 
  summarize(Demo_Score = sum(Demo_Score, na.rm = TRUE)) %>% 
  pivot_wider(id_cols=Engagement_Score, names_from = "Category", values_from = "Demo_Score")
                                                                        

error_metrics <- function(model_name,actual, pred, mode){
  mae <- mean(abs(actual - pred))
  rmse <- sqrt(mean((actual - pred)^2))
  mape <- mean(abs(actual - pred) / actual)
  result <- data.frame(Model=model_name,MAE=mae, RMSE=rmse,
                       MAPE = mape, Mode=mode)
  
  return (result)
}

# dtree <- df_summary3 %>% 
#   select(-Account_Creation, -Homepage, -Job_Alert_Sign_Up,
#         -Job_Apply, -View_Job, -Duration, -Network.2, -Network,
#         -duration15_percent, -duration30_percent, -duration60_percent, -Show, 
#         -total_imp)


################################ Stepwise Regression and Regularization ####################
set.seed(1234)
trainIndex <- sample(1:nrow(df_summary5), round(0.75* nrow(df_summary5)))


### Stepwise Regression ####

df_step_train <- df_summary5[trainIndex,]
df_step_test <- df_summary5[-trainIndex,]


full_model <- lm(Engagement_Score~., data=df_step_train)
null_model <- lm(Engagement_Score~1, data = df_step_train)

step_model <- step(null_model, 
                   list(lower=formula(null_model), upper=formula(full_model)), 
                   direction="both")
summary(step_model)
#print(car::vif(step_model))
tidy(step_model)

step_vif <- car::vif(step_model)
step_vif_df <- data.frame(Variables = names(step_vif),
                          VIF = step_vif)

step_result_train <- error_metrics("Stepwise Regression",df_step_train$Engagement_Score,
                                  predict(step_model), "Train")

step_pred <- predict(step_model, newdata = df_step_test)
step_result_validate <- error_metrics("Stepwise Regression",df_step_test$Engagement_Score,
                                  step_pred, "Validation")

###### Regularization ######

df_rg_train <- df_summary5[trainIndex,]
df_rg_test <- df_summary5[-trainIndex,]

# No need to scale the numeric data since every predictor is in percentage
lambdas <- 10^seq(2,-2, by=-0.01)

X_train <- as.matrix(df_rg_train %>% select(-Engagement_Score))
X_test <- as.matrix(df_rg_test %>% select(-Engagement_Score))

### Ridge Regression ###

ridge_model <- cv.glmnet(X_train, df_rg_train$Engagement_Score,
                         alpha=0, lambda = lambdas)

ridge_opt_lambda <- ridge_model$lambda.min

ridge_result_train <- error_metrics("Ridge Regression",
                                  df_rg_train$Engagement_Score,
                                  predict(ridge_model, newx=X_train, s=ridge_opt_lambda),
                                  "Train")

ridge_result_validate <- error_metrics("Ridge Regression",
                                    df_rg_test$Engagement_Score,
                                    predict(ridge_model, newx=X_test, s=ridge_opt_lambda),
                                   "Validation")

ridge_best_mod <- glmnet(X_train, df_rg_train$Engagement_Score, alpha=0, 
                         lambda=ridge_opt_lambda)
ridge_best_summary <- as.data.frame(as.matrix(coef(ridge_best_mod)))

ridge_best_summary$Variables <- row.names(ridge_best_summary)
row.names(ridge_best_summary) <- NULL
colnames(ridge_best_summary)[1] <- "Coefficients"
ridge_best_summary <- ridge_best_summary %>% select(Variables, Coefficients)

### Lasso Regression ###

lasso_model <- cv.glmnet(X_train, df_rg_train$Engagement_Score,
                         alpha=1, lambda = lambdas)

lasso_opt_lambda <- lasso_model$lambda.min

lasso_result_train <- error_metrics("Lasso Regression",
                                    df_rg_train$Engagement_Score,
                                    predict(ridge_model, newx=X_train, s=lasso_opt_lambda),
                                    "Train")

lasso_result_validate <- error_metrics("Lasso Regression",
                                   df_rg_test$Engagement_Score,
                                   predict(ridge_model, newx=X_test, s=lasso_opt_lambda),
                                   "Validation")
lasso_best_mod <- glmnet(X_train, df_rg_train$Engagement_Score, alpha=1, 
                         lambda=lasso_opt_lambda)
lasso_best_summary <- as.data.frame(as.matrix(coef(lasso_best_mod)))

lasso_best_summary$Variables <- row.names(lasso_best_summary)
row.names(lasso_best_summary) <- NULL
colnames(lasso_best_summary)[1] <- "Coefficients"
lasso_best_summary <- lasso_best_summary %>% select(Variables, Coefficients)

### ElasticNet ###

enet_control <- trainControl(method="repeatedcv",
                            number=10,
                            repeats = 5,
                            search = "random")

enet_model <- train(Engagement_Score~.,
                    data = df_rg_train,
                    method = "glmnet",
                    trControl = enet_control)

enet_result_train <- error_metrics("Elastic Net",df_rg_train$Engagement_Score,
                                   predict(enet_model, df_rg_train),"Train")
enet_result_validate <- error_metrics("Elastic Net",df_rg_test$Engagement_Score,
                                  predict(enet_model, df_rg_test), "Validation")

enet_coef <- coef(enet_model$finalModel, enet_model$bestTune$lambda)
enet_best_summary <- as.data.frame(as.matrix(enet_coef))

enet_best_summary$Variables <- row.names(enet_best_summary)
row.names(enet_best_summary) <- NULL
colnames(enet_best_summary)[1] <- "Coefficients"
enet_best_summary <- enet_best_summary %>% select(Variables, Coefficients)

################################ Decision Tree and Random Forest ########

dtree <- df_summary5
colnames(dtree) <- make.names(colnames(dtree))

drf <- dtree

#### Decision Tree
set.seed(1234)

trainIndex <- createDataPartition(dtree$Engagement_Score, p=0.75, list = FALSE)
dtree_train <- dtree[trainIndex,]
dtree_test <- dtree[-trainIndex, ]

tree_model <- train(Engagement_Score~.,
                    data = dtree_train,
                    method="rpart",
                    trControl=trainControl(method="repeatedcv", number=3, repeats=5),
                    control = rpart.control(minsplit = 20, cp=0.01, maxdepth=3)
)

tree_result_train <- tree_result_test <- error_metrics("Decision Tree",dtree_train$Engagement_Score,
                                                       predict(tree_model), "Train")

tree_pred <- predict(tree_model, dtree_test)
tree_result_validate <- error_metrics("Decision Tree",dtree_test$Engagement_Score,
                                  tree_pred, "Validation")


fancyRpartPlot(tree_model$finalModel)

### Bar Plot
dtree_importance <- tree_model$finalModel$variable.importance
dtree_importance_tbl <- data.frame(Variables = names(dtree_importance),
                                   Importance = dtree_importance)
dtree_importance_tbl <- dtree_importance_tbl %>% 
  inner_join(category_mapping, by=c("Variables"="Alias"))

dtree_importance_tbl <- dtree_importance_tbl %>% arrange(-Importance) %>% 
  select(-Variables) %>% rename("Variables"="Model_Category")

ggplot(dtree_importance_tbl %>% head(10), aes(x=reorder(Variables,Importance), y=Importance, fill=Variables)) + 
  geom_col() +
  coord_flip() + labs(x="Variables", y="Importance") +
  theme(legend.position = "none") + 
  labs(title="Top 10 Category Variables: Decision Tree", x="Category Variables")

#### Random Forest
set.seed(1234)
model_control <- trainControl(method="cv", number=10)
train_index <- createDataPartition(drf$Engagement_Score,p=0.75,list=FALSE)

drf_train <- drf[trainIndex,]
drf_test <- drf[-trainIndex,]


rf_grid <- expand.grid(mtry= c(5,10,15),
                       splitrule = c("extratrees"),
                       min.node.size=c(5,10,15,20,25,30))

rf_model <- train(Engagement_Score~.,
                  data = drf_train,
                  method = "ranger",
                  trControl = model_control,
                  tuneGrid = rf_grid,
                  importance="permutation")

print(varImp(rf_model))


importance_tbl <- varImp(rf_model)$importance
colnames(importance_tbl)[1] <- "Importance"
importance_tbl$Variables <- row.names(importance_tbl)
row.names(importance_tbl) <- NULL

importance_tbl <- importance_tbl %>% inner_join(category_mapping, by=c("Variables"="Alias"))


importance_tbl <- importance_tbl %>% arrange(-Importance) %>% select(-Variables) %>%
                  rename("Variables"="Model_Category")

ggplot(importance_tbl %>% head(10), aes(x=reorder(Variables,Importance), y=Importance, fill=Variables)) + 
  geom_col() +
  coord_flip() + labs(x="Variables", y="Importance") +
  theme(legend.position = "none") + labs(title="Top 10 Category Variables: Random Forest", x="Category Variables")

rf_result_train <- error_metrics("Random Forest",drf_train$Engagement_Score, 
                                rf_model$finalModel$predictions, "Train")


rf_pred <- predict(rf_model, newdata=drf_test)
rf_result_validate <- error_metrics("Random Forest",drf_test$Engagement_Score, 
                                rf_pred, "Validation")


###### Model Performance Eval ###########
# performance_final <- bind_rows(step_result_train, step_result_validate,
#                                ridge_result_train, ridge_result_validate,
#                                lasso_result_train, lasso_result_validate,
#                                enet_result_train, enet_result_validate,
#                                tree_result_train, tree_result_validate,
#                                rf_result_train, rf_result_validate)

performance_final <- bind_rows(step_result_train, ridge_result_train,
                               lasso_result_train,enet_result_train,
                               tree_result_train,rf_result_train,
                               step_result_validate,ridge_result_validate,
                               lasso_result_validate,enet_result_validate,
                               tree_result_validate,rf_result_validate)

####### Test Set for those networks not originally in the training data ##########

df_test_set1 <- read.csv("Test Set.csv") # for tree based models
df_test_set2 <- read_csv("Test Set.csv") # for stepwise, regularization models

pred_test_step <- predict(step_model, newdata = df_test_set2)
pred_test_enet <- predict(enet_model, newdata = df_test_set2)

pred_test_dtree <- predict(tree_model, newdata = df_test_set1)
pred_test_rf <- predict(rf_model, newdata = df_test_set1)

step_result_test <- error_metrics("Stepwise Regression",df_test_set2$Engagement_Score,
                                  pred_test_step,"Test")


######## For Lasso and Ridge
X_test_new <- as.matrix(df_test_set2 %>% select(-Engagement_Score))

ridge_result_test <- error_metrics("Ridge Regression",df_test_set2$Engagement_Score,
                                   predict(ridge_model, newx=X_test_new, s=ridge_opt_lambda)
                                   ,"Test")

lasso_result_test <- error_metrics("Lasso Regression",df_test_set2$Engagement_Score,
                                   predict(lasso_model, newx=X_test_new, s=lasso_opt_lambda),"Test")

############## Using SMB Data ########################################################

enet_result_test <- error_metrics("Elastic Net",df_test_set2$Engagement_Score,
                                  pred_test_enet,"Test")

tree_result_test <- error_metrics("Decision Tree",df_test_set1$Engagement_Score,
                                  pred_test_dtree,"Test")

rf_result_test <- error_metrics("Random Forest",df_test_set1$Engagement_Score,
                                  pred_test_rf,"Test")


performance_final <- rbind(performance_final, step_result_test,
                           ridge_result_test, lasso_result_test,
                           enet_result_test, tree_result_test,
                           rf_result_test)


##### Predicting Results with Network not in training set ##################################

df_new_test <- total_q_demo %>% filter(!Network %in% unique(df_summary4$Network))
df_new_test_long <- df_new_test %>% 
  pivot_longer(-Network, names_to = "Demo_Q", values_to = "Demo_Score")
df_new_test_long <- df_new_test_long %>% inner_join(question_mapping, by=c("Demo_Q"="Attributes"))

df_new_test_wide <- df_new_test_long %>% group_by(Category, Network) %>% 
  summarize(Demo_Score = sum(Demo_Score, na.rm = TRUE)) %>% 
  pivot_wider(id_cols=Network, names_from = "Category", values_from = "Demo_Score")

df_new_test_tree <- df_new_test_wide
df_new_test_linear <- df_new_test_wide
colnames(df_new_test_tree) <- make.names(colnames(df_new_test_tree))

# Tree Based Model
rf_new_pred <- exp(predict(rf_model, newdata = df_new_test_tree)) # response variable is on log scale, 
                                                                  #using exp to convert
dtree_new_pred <- exp(predict(tree_model, newdata = df_new_test_tree))

# Linear Model
step_new_pred <- exp(predict(step_model, newdata = df_new_test_linear))

X_test_new2 <- as.matrix(df_new_test_linear %>% select(-Network)) 
ridge_new_pred <- as.numeric(exp(predict(ridge_model, newx=X_test_new2, s=ridge_opt_lambda)))
lasso_new_pred <- as.numeric(exp(predict(lasso_model, newx=X_test_new2, s=lasso_opt_lambda)))

enet_new_pred <- exp(predict(enet_model, newdata = df_new_test_linear))

df_new_result <- data.frame(Network = df_new_test_wide$Network,
                            Random_Forest = rf_new_pred, Decision_Tree = dtree_new_pred,
                            Step_Regression = step_new_pred, Ridge_Regression = ridge_new_pred,
                            Lasso_Regression = lasso_new_pred, ElasticNet = enet_new_pred)

write.csv(df_new_result, "Engagement Score for Networks not in Training Set.csv", row.names = FALSE)
