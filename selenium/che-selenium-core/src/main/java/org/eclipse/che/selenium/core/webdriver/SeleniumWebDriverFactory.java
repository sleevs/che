/*
 * Copyright (c) 2012-2018 Red Hat, Inc.
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *
 * Contributors:
 *   Red Hat, Inc. - initial API and implementation
 */
package org.eclipse.che.selenium.core.webdriver;

import com.google.inject.Inject;
import com.google.inject.Singleton;
import com.google.inject.name.Named;
import org.eclipse.che.selenium.core.SeleniumWebDriver;
import org.eclipse.che.selenium.core.constant.TestBrowser;

/** @author Dmytro Nochevnov */
@Singleton
public class SeleniumWebDriverFactory {

  @Inject
  @Named("sys.browser")
  TestBrowser browser;

  @Inject
  @Named("sys.driver.port")
  private String webDriverPort;

  @Inject
  @Named("sys.grid.mode")
  private boolean gridMode;

  @Inject
  @Named("sys.driver.version")
  private String webDriverVersion;

  @Inject
  @Named("tests.download_dir")
  private String downloadDirectory;

  public SeleniumWebDriver create() {
    return new SeleniumWebDriver(
        browser, webDriverPort, gridMode, webDriverVersion, downloadDirectory);
  }
}
