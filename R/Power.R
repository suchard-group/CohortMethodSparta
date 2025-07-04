# @file Power.R
#
# Copyright 2025 Observational Health Data Sciences and Informatics
#
# This file is part of CohortMethod
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#' Compute the minimum detectable relative risk
#'
#' @details
#' Compute the minimum detectable relative risk (MDRR) and expected standard error (SE) for a given
#' study population, using the actual observed sample size and number of outcomes. Currently, only
#' computations for Cox and logistic models are implemented. For Cox model, the computations by
#' Schoenfeld (1983) is used. For logistic models Wald's z-test is used.
#'
#' @param population   A data frame describing the study population as created using the
#'                     \code{\link{createStudyPopulation}} function. This should at least have these
#'                     columns: personSeqId, treatment, outcomeCount, timeAtRisk.
#' @param alpha        Type I error.
#' @param power        1 - beta, where beta is the type II error.
#' @param twoSided     Consider a two-sided test?
#' @param modelType    The type of outcome model that will be used. Possible values are
#'                     "logistic", "poisson", or "cox". Currently only "cox" is supported.
#'
#' @references
#' Schoenfeld DA (1983) Sample-size formula for the proportional-hazards regression model, Biometrics,
#' 39(3), 499-503
#'
#' @return
#' A data frame with the MDRR and some counts.
#'
#' @export
computeMdrr <- function(population, alpha = 0.05, power = 0.8, twoSided = TRUE, modelType = "cox") {
  errorMessages <- checkmate::makeAssertCollection()
  checkmate::assertDataFrame(population, add = errorMessages)
  checkmate::assertNumber(alpha, lower = 0, upper = 1, add = errorMessages)
  checkmate::assertNumber(power, lower = 0, upper = 1, add = errorMessages)
  checkmate::assertLogical(twoSided, len = 1, add = errorMessages)
  checkmate::assertChoice(modelType, c("cox", "logistic"), add = errorMessages)
  checkmate::reportAssertions(collection = errorMessages)

  pTarget <- mean(population$treatment)
  totalEvents <- sum(population$outcomeCount != 0)
  totalSubjects <- nrow(population)
  mdrr <- computeMdrrFromAggregateStats(
    pTarget = pTarget,
    totalEvents = totalEvents,
    totalSubjects = totalSubjects,
    alpha = alpha,
    power = power,
    twoSided = twoSided,
    modelType = modelType
  )
  se <- 1 / sqrt(totalEvents * pTarget * (1 - pTarget))
  result <- data.frame(
    targetPersons = length(unique(population$personSeqId[population$treatment == 1])),
    comparatorPersons = length(unique(population$personSeqId[population$treatment == 0])),
    targetExposures = sum(population$treatment == 1),
    comparatorExposures = sum(population$treatment == 0),
    targetDays = sum(population$timeAtRisk[population$treatment == 1]),
    comparatorDays = sum(population$timeAtRisk[population$treatment == 0]),
    totalOutcomes = totalEvents,
    mdrr = mdrr,
    se = se
  )
  return(result)
}

computeMdrrFromAggregateStats <- function(pTarget, totalEvents, totalSubjects, alpha = 0.05, power = 0.8, twoSided = TRUE, modelType = "cox") {
  if (totalEvents == 0) {
    return(Inf)
  }
  if (twoSided) {
    z1MinAlpha <- qnorm(1 - alpha / 2)
  } else {
    z1MinAlpha <- qnorm(1 - alpha)
  }
  if (modelType == "cox") {
    zBeta <- -qnorm(1 - power)
    pComparator <- 1 - pTarget
    mdrr <- exp(sqrt((zBeta + z1MinAlpha)^2 / (totalEvents * pTarget * pComparator)))
  } else if (modelType == "logistic") {
    pBaseline <- totalEvents / totalSubjects
    se <- sqrt((1 / (totalEvents * (1 - pBaseline))))
    fun <- function(z) {
      pnorm(z - z1MinAlpha) - power
    }
    z <- uniroot(fun, c(0, 1e+07))$root
    mdrr <- exp(z * se)
  } else {
    stop("Unknown model type: ", modelType)
  }
  return(mdrr)
}

#' Get the distribution of follow-up time
#'
#' @details
#' Get the distribution of follow-up time as quantiles. Follow-up time is defined as time-at-risk, so
#' not censored at the outcome.
#'
#' @param population   A data frame describing the study population as created using the
#'                     \code{\link{createStudyPopulation}} function. This should at least have these
#'                     columns: treatment, timeAtRisk.
#' @param quantiles    The quantiles of the population to compute minimum follow-up time for.
#'
#'
#' @return
#' A data frame with per treatment group at each quantile the amount of follow-up time available.
#'
#' @export
getFollowUpDistribution <- function(population, quantiles = c(0, 0.25, 0.5, 0.75, 1)) {
  errorMessages <- checkmate::makeAssertCollection()
  checkmate::assertDataFrame(population, add = errorMessages)
  checkmate::assertNumeric(quantiles, lower = 0, upper = 1, min.len = 1, add = errorMessages)
  checkmate::reportAssertions(collection = errorMessages)

  population <- population[order(population$timeAtRisk), ]
  target <- quantile(population$timeAtRisk[population$treatment == 1], quantiles)
  comparator <- quantile(population$timeAtRisk[population$treatment == 0], quantiles)
  result <- rbind(as.data.frame(t(target)), as.data.frame(t(comparator)))
  names(result) <- rev(names(result))
  result$Treatment <- c(1, 0)
  return(result)
}

#' Plot the distribution of follow-up time
#'
#' @details
#' Plot the distribution of follow-up time, stratified by treatment group.Follow-up time is defined as
#' time-at-risk, so not censored at the outcome.
#'
#' @param population        A data frame describing the study population as created using the
#'                          \code{\link{createStudyPopulation}} function. This should at least have
#'                          these columns: treatment, timeAtRisk.
#' @param targetLabel       A label to us for the target cohort.
#' @param comparatorLabel   A label to us for the comparator cohort.
#' @param yScale            Should be either 'percent' or 'count'.
#' @param logYScale         Should the Y axis be on the log scale?
#' @param dataCutoff        Fraction of the data (number censored) after which the graph will not be
#'                          shown.
#' @param title             The main title of the plot.
#' @param fileName          Name of the file where the plot should be saved, for example 'plot.png'.
#'                          See the function \code{ggsave} in the ggplot2 package for supported file
#'                          formats.
#'
#' @return
#' A ggplot object. Use the \code{\link[ggplot2]{ggsave}} function to save to file in a different
#' format.
#'
#' @export
plotFollowUpDistribution <- function(population,
                                     targetLabel = "Target",
                                     comparatorLabel = "Comparator",
                                     yScale = "percent",
                                     logYScale = FALSE,
                                     dataCutoff = 0.95,
                                     title = NULL,
                                     fileName = NULL) {
  errorMessages <- checkmate::makeAssertCollection()
  checkmate::assertDataFrame(population, add = errorMessages)
  checkmate::assertCharacter(targetLabel, len = 1, add = errorMessages)
  checkmate::assertCharacter(comparatorLabel, len = 1, add = errorMessages)
  checkmate::assertChoice(yScale, c("percent", "count"), add = errorMessages)
  checkmate::assertLogical(logYScale, len = 1, add = errorMessages)
  checkmate::assertNumber(dataCutoff, lower = 0, upper = 1, add = errorMessages)
  checkmate::assertCharacter(title, len = 1, null.ok = TRUE, add = errorMessages)
  checkmate::assertCharacter(fileName, len = 1, null.ok = TRUE, add = errorMessages)
  checkmate::reportAssertions(collection = errorMessages)

  if (yScale == "percent") {
    yLabel <- "Percent of subjects (cumulative)"
  } else {
    yLabel <- "Number of subjects (cumulative)"
  }
  population <- population[order(-population$timeAtRisk), ]
  cutoff <- quantile(population$timeAtRisk, dataCutoff)
  target <- data.frame(followUp = population$timeAtRisk[population$treatment == 1], count = 1)
  target$sumCount <- cumsum(target$count)
  target <- aggregate(sumCount ~ followUp, data = target, max)
  target0 <- data.frame(followUp = 0, sumCount = target$sumCount[1])
  target <- rbind(target0, target)
  if (yScale == "percent") {
    target$sumCount <- 100 * target$sumCount / target$sumCount[1]
  }
  comparator <- data.frame(followUp = population$timeAtRisk[population$treatment == 0], count = 1)
  comparator$sumCount <- cumsum(comparator$count)
  comparator <- aggregate(sumCount ~ followUp, data = comparator, max)
  comparator0 <- data.frame(followUp = 0, sumCount = comparator$sumCount[1])
  comparator <- rbind(comparator0, comparator)
  if (yScale == "percent") {
    comparator$sumCount <- 100 * comparator$sumCount / comparator$sumCount[1]
  }
  target$label <- as.character(targetLabel)
  comparator$label <- as.character(comparatorLabel)
  d <- rbind(target, comparator)
  d$label <- factor(d$label, levels = c(targetLabel, comparatorLabel))
  plot <- ggplot2::ggplot(
    d,
    ggplot2::aes(x = .data$followUp, y = .data$sumCount, group = .data$label, color = .data$label)
  ) +
    ggplot2::geom_hline(yintercept = 0) +
    ggplot2::geom_step(size = 1) +
    ggplot2::scale_color_manual(values = c(
      rgb(0.8, 0, 0, alpha = 0.5),
      rgb(0, 0, 0.8, alpha = 0.5)
    )) +
    ggplot2::scale_x_continuous("Follow-up (days)") +
    ggplot2::coord_cartesian(xlim = c(0, cutoff)) +
    ggplot2::theme(
      legend.title = ggplot2::element_blank(),
      legend.position = "top",
    )
  if (logYScale) {
    plot <- plot + ggplot2::scale_y_log10(yLabel)
  } else {
    plot <- plot + ggplot2::scale_y_continuous(yLabel)
  }
  if (!is.null(title)) {
    plot <- plot + ggplot2::ggtitle(title)
  }
  if (!is.null(fileName)) {
    ggplot2::ggsave(fileName, plot, width = 5, height = 3.5, dpi = 400)
  }
  return(plot)
}
