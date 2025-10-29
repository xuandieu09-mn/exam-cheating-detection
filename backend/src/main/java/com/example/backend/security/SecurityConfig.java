package com.example.backend.security;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
public class SecurityConfig {

  @Bean
  SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http
      .csrf(csrf -> csrf.disable())             // dev: tắt CSRF cho dễ test
      .authorizeHttpRequests(auth -> auth
        // Cho phép không cần đăng nhập các API bạn đang test
        .requestMatchers("/health", "/sessions/**").permitAll()
        // Hoặc mở toàn bộ trong giai đoạn dev:
        .anyRequest().permitAll()
      )
      .httpBasic(httpBasic -> {})               // để test cũng được
      .formLogin(form -> form.disable());       // tắt trang login mặc định
    return http.build();
  }
}