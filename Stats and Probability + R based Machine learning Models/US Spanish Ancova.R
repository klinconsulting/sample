library(tidyverse)
library(ggplot2)
library(plyr)
library(dplyr)
library(lubridate)

ancova_df <- read.csv("US Spanish Test data 4.27.21.csv")
ancova_df$Month <- as.Date(ancova_df$Month, "%m/%d/%Y")
ancova_df$Value <- as.numeric(ancova_df$Value)

ancova_df_summary <- ancova_df %>% group_by(KPI,Group) %>%
  dplyr::summarize(KPI_Avg = mean(Value, na.rm=TRUE))

aov_list <- ancova_df %>% group_by(KPI) %>% 
  group_map(~ aov(.x$Value~.x$Group), .keep=TRUE)
  
aov_table <- function(x){
  
  dep_var <- "Value"
  F_stat <- summary(x)[[1]][1,4] # grab F-statistic from the anova table
  p_value <- summary(x)[[1]][1,5]
  return (data.frame(Dependent=dep_var, F_stat = F_stat, p_value = p_value))
}

# ANOVA analysis is needed for categorical indep variables vs. binary dep. variable
aov_summary <- ldply(aov_list, aov_table)
aov_summary <- aov_summary %>% mutate(Independent = "Group: Control vs. Test",
                                      KPI=ancova_df %>% group_by(KPI) %>% group_keys()%>% pull(), Reject_Null = ifelse(p_value < 0.05, 1, 0))
aov_summary <- aov_summary %>% select(Dependent, Independent,KPI, F_stat, p_value, Reject_Null)
result <- aov_summary %>% arrange(desc(Reject_Null))
print(result)

write.csv(result, "ANOVA US Spanish Test.csv", row.names = FALSE)
